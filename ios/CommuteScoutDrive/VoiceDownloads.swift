import Foundation
import UIKit

/// Downloads, checks and deletes the CommuteScout voice packs.
///
/// Each file of a pack is its own download (the per-file release assets
/// in `shared/voices.json`), on a background URLSession so it carries on
/// when the driver leaves the app. A cancelled or failed file keeps what
/// it has: as resume data from URLSession, or as a `.part` file that a
/// `Range` request continues. A finished file is checked against the
/// catalog's size and sha256 before it gets its own name, and the pack
/// counts as installed only when every file has passed.
@MainActor
final class VoicePacks: ObservableObject {
    static let shared = VoicePacks()
    static let sessionId = "com.commutescout.drive.voices"

    enum State: Equatable {
        case none
        case downloading(done: Int64, total: Int64)
        case paused(done: Int64, total: Int64)
        case installed
        case failed(String)
    }

    @Published private(set) var states: [String: State] = [:]
    /// Set by the app delegate when iOS wakes the app for finished
    /// background downloads; called once the session has delivered them.
    var backgroundCompletion: (() -> Void)?

    let catalog = VoiceCatalog.bundled
    private var session: URLSession!
    private let delegate = VoiceDownloadDelegate()
    /// Bytes received per file ("pack/file"), for the progress bar.
    private var received: [String: Int64] = [:]
    private var running: [String: Set<String>] = [:]   // pack -> files with a task
    private var retries: [String: Int] = [:]
    private var pausing: Set<String> = []
    private var lastPublish: [String: Date] = [:]

    // MARK: installed packs, readable from any thread

    private nonisolated static let lock = NSLock()
    private nonisolated(unsafe) static var installed: Set<String>?

    /// Packs on the phone whose files are all there and the right size.
    /// Worked out from the disk on first use, then kept up to date.
    nonisolated static var installedIds: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        if let installed { return installed }
        let found = Set((VoiceCatalog.bundled?.packs ?? []).filter { VoicePackFiles.installedAndIntact($0) }.map(\.id))
        installed = found
        return found
    }

    private nonisolated static func setInstalled(_ id: String, _ on: Bool) {
        _ = installedIds
        lock.lock()
        if on { installed?.insert(id) } else { installed?.remove(id) }
        lock.unlock()
        Voice.refresh()
    }

    private init() {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionId)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        // Each request says whether it may use cellular data.
        config.allowsCellularAccess = true
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        launchCheck()
        session.getAllTasks { tasks in
            let found = tasks.compactMap { t -> (String, String)? in
                guard t.state == .running || t.state == .suspended, let d = VoiceDownloadDelegate.parse(t.taskDescription) else { return nil }
                return (d.pack, d.file)
            }
            Task { @MainActor in
                for (pack, file) in found { VoicePacks.shared.running[pack, default: []].insert(file) }
                for pack in Set(found.map(\.0)) { VoicePacks.shared.publish(pack, force: true) }
            }
        }
    }

    /// Called at launch: re-check the sizes of every installed pack, and
    /// put each pack's state together from what is on disk. A pack that
    /// was installed but no longer matches the catalog, because this
    /// version of the app ships new model files or a file was damaged,
    /// fetches just those files again, on Wi-Fi unless the driver allowed
    /// mobile data before. The chosen voice stays chosen; the system
    /// voice speaks until the files are in.
    private func launchCheck() {
        guard let catalog else { return }
        for pack in catalog.packs {
            let dir = VoicePackFiles.directory(pack.id)
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(VoicePackFiles.marker).path) {
                let stale = VoicePackFiles.removeStale(pack)
                let broken = VoicePackFiles.unmarkBroken(pack)
                if !broken.isEmpty {
                    DriveLog.note("voices: \(pack.id) needs \(broken.joined(separator: ", "))\(stale.isEmpty ? "" : " (removed \(stale.joined(separator: ", ")))"); updating")
                    Self.setInstalled(pack.id, false)
                    download(pack.id, cellular: UserDefaults.standard.bool(forKey: "cs.voices.cellular.\(pack.id)"))
                }
            }
            publish(pack.id, force: true)
        }
    }

    func state(_ packId: String) -> State { states[packId] ?? .none }

    /// Something looked wrong when the engine loaded: check again.
    func recheck() {
        guard let catalog else { return }
        for pack in catalog.packs where Self.installedIds.contains(pack.id) && !VoicePackFiles.installedAndIntact(pack) {
            let broken = VoicePackFiles.unmarkBroken(pack)
            DriveLog.note("voices: \(pack.id) damaged (\(broken.joined(separator: ", "))); using the system voice")
            Self.setInstalled(pack.id, false)
            publish(pack.id, force: true)
        }
    }

    private func publish(_ packId: String, force: Bool = false) {
        guard let pack = catalog?.pack(packId) else { return }
        let now = Date()
        if !force, let t = lastPublish[packId], now.timeIntervalSince(t) < 0.25 { return }
        lastPublish[packId] = now
        let new: State
        if Self.installedIds.contains(packId) {
            new = .installed
        } else if case let .failed(why) = states[packId], running[packId, default: []].isEmpty {
            new = .failed(why)
        } else {
            let done = doneBytes(pack)
            if !running[packId, default: []].isEmpty && !pausing.contains(packId) {
                new = .downloading(done: done, total: pack.downloadSize)
            } else if VoicePackFiles.hasAnything(packId) {
                new = .paused(done: done, total: pack.downloadSize)
            } else {
                new = .none
            }
        }
        if states[packId] != new { states[packId] = new }
    }

    private func doneBytes(_ pack: VoiceCatalog.Pack) -> Int64 {
        let dir = VoicePackFiles.directory(pack.id)
        return pack.files.reduce(0) { sum, f in
            if VoicePackFiles.size(dir.appendingPathComponent(f.name)) == f.size { return sum + f.size }
            let part = max(received["\(pack.id)/\(f.name)"] ?? 0, VoicePackFiles.size(VoicePackFiles.partURL(f, in: dir)) ?? 0)
            return sum + min(part, f.size)
        }
    }

    // MARK: actions

    enum StartProblem: Equatable {
        case noSpace(needed: Int64)
    }

    /// Checks free space for what is left plus 10%.
    func problem(_ packId: String) -> StartProblem? {
        guard let pack = catalog?.pack(packId) else { return nil }
        let needed = VoicePackFiles.neededBytes(pack)
        if let free = VoicePackFiles.freeBytes(), free < needed { return .noSpace(needed: needed) }
        return nil
    }

    /// Download, or resume, every file of a pack that is not yet on the
    /// phone. With `cellular` false the download waits for Wi-Fi.
    func download(_ packId: String, cellular: Bool) {
        guard let pack = catalog?.pack(packId) else { return }
        if case let .noSpace(needed) = problem(packId) {
            states[packId] = .failed("Not enough space. The download needs \(VoicePackFiles.label(needed)) free.")
            return
        }
        do { try VoicePackFiles.prepare(packId) } catch {
            states[packId] = .failed("Could not save the voices on this phone.")
            return
        }
        pausing.remove(packId)
        if case .failed = states[packId] { states[packId] = nil }
        UserDefaults.standard.set(cellular, forKey: "cs.voices.cellular.\(packId)")
        let dir = VoicePackFiles.directory(packId)
        DriveLog.note("voices: downloading \(packId)\(cellular ? " (cellular allowed)" : " (Wi-Fi only)")")
        for f in pack.files where VoicePackFiles.size(dir.appendingPathComponent(f.name)) != f.size {
            if running[packId, default: []].contains(f.name) { continue }
            start(pack, f, cellular: cellular)
        }
        finishIfComplete(pack)
        publish(packId, force: true)
    }

    private func start(_ pack: VoiceCatalog.Pack, _ f: VoiceCatalog.Pack.File, cellular: Bool) {
        let dir = VoicePackFiles.directory(pack.id)
        let resume = VoicePackFiles.resumeURL(f, in: dir)
        let part = VoicePackFiles.partURL(f, in: dir)
        let task: URLSessionDownloadTask
        if let data = try? Data(contentsOf: resume) {
            try? FileManager.default.removeItem(at: resume)
            task = session.downloadTask(withResumeData: data)
            task.taskDescription = VoiceDownloadDelegate.describe(pack.id, f.name, mode: "resume")
        } else {
            var request = URLRequest(url: f.url)
            request.allowsCellularAccess = cellular
            request.allowsExpensiveNetworkAccess = cellular
            request.allowsConstrainedNetworkAccess = cellular
            let have = VoicePackFiles.size(part) ?? 0
            var mode = "full"
            if have > 0, have < f.size {
                request.setValue("bytes=\(have)-", forHTTPHeaderField: "Range")
                mode = "range:\(have)"
            } else if have >= f.size {
                try? FileManager.default.removeItem(at: part)
            }
            task = session.downloadTask(with: request)
            task.taskDescription = VoiceDownloadDelegate.describe(pack.id, f.name, mode: mode)
        }
        task.countOfBytesClientExpectsToReceive = f.size
        running[pack.id, default: []].insert(f.name)
        task.resume()
    }

    /// Stop the download and keep what has arrived, to resume later.
    func pause(_ packId: String) {
        pausing.insert(packId)
        DriveLog.note("voices: \(packId) download cancelled; partial files kept")
        session.getAllTasks { tasks in
            for t in tasks {
                guard let d = VoiceDownloadDelegate.parse(t.taskDescription), d.pack == packId else { continue }
                guard let download = t as? URLSessionDownloadTask else { t.cancel(); continue }
                download.cancel(byProducingResumeData: { data in
                    guard let data, let pack = VoiceCatalog.bundled?.pack(packId),
                          let f = pack.files.first(where: { $0.name == d.file }),
                          let dir = try? VoicePackFiles.prepare(packId) else { return }
                    try? data.write(to: VoicePackFiles.resumeURL(f, in: dir))
                })
            }
        }
        publish(packId, force: true)
    }

    /// Remove the pack and anything partial: the space comes back.
    func delete(_ packId: String) {
        pausing.insert(packId)
        session.getAllTasks { tasks in
            for t in tasks where VoiceDownloadDelegate.parse(t.taskDescription)?.pack == packId { t.cancel() }
            Task { @MainActor in
                // No new engine load starts once the marker is gone; the
                // files go after any load or render in progress ends.
                try? FileManager.default.removeItem(at: VoicePackFiles.directory(packId).appendingPathComponent(VoicePackFiles.marker))
                VoicePacks.setInstalled(packId, false)
                NeuralVoices.shared.forget(packId: packId) {
                    VoicePackFiles.remove(packId)
                    Task { @MainActor in VoicePacks.shared.publish(packId, force: true) }
                }
                VoicePacks.shared.running[packId] = nil
                VoicePacks.shared.received = VoicePacks.shared.received.filter { !$0.key.hasPrefix(packId + "/") }
                if case .failed = VoicePacks.shared.states[packId] { VoicePacks.shared.states[packId] = nil }
                VoicePacks.shared.publish(packId, force: true)
                VoicePacks.shared.pausing.remove(packId)
            }
        }
        DriveLog.note("voices: \(packId) deleted")
    }

    private func finishIfComplete(_ pack: VoiceCatalog.Pack) {
        guard !Self.installedIds.contains(pack.id), running[pack.id, default: []].isEmpty,
              VoicePackFiles.brokenFiles(pack).isEmpty else { return }
        if VoicePackFiles.markInstalledIfComplete(pack) {
            VoicePackFiles.removeStale(pack)
            NeuralVoices.shared.forget(packId: pack.id)
            Self.setInstalled(pack.id, true)
            DriveLog.note("voices: \(pack.id) installed (\(VoicePackFiles.label(pack.downloadSize)))")
        }
        publish(pack.id, force: true)
    }

    // MARK: from the session delegate

    fileprivate func progress(_ pack: String, _ file: String, bytes: Int64) {
        received["\(pack)/\(file)"] = bytes
        publish(pack)
    }

    fileprivate func fileDone(_ packId: String, _ file: String, outcome: VoiceDownloadDelegate.Outcome) {
        guard let pack = catalog?.pack(packId), let f = pack.files.first(where: { $0.name == file }) else { return }
        running[packId]?.remove(file)
        received["\(packId)/\(file)"] = nil
        let key = "\(packId)/\(file)"
        switch outcome {
        case .verified:
            retries[key] = nil
            finishIfComplete(pack)
        case .cancelled:
            break
        case let .retry(why):
            let n = (retries[key] ?? 0) + 1
            retries[key] = n
            if pausing.contains(packId) { break }
            if n <= 3 {
                DriveLog.note("voices: \(file) \(why); trying again (\(n) of 3)")
                let cellular = UserDefaults.standard.bool(forKey: "cs.voices.cellular.\(packId)")
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(n) * 2_000_000_000)
                    guard !self.pausing.contains(packId), !self.running[packId, default: []].contains(file) else { return }
                    self.start(pack, f, cellular: cellular)
                    self.publish(packId, force: true)
                }
            } else {
                DriveLog.note("voices: \(file) \(why); giving up")
                retries[key] = nil
                states[packId] = .failed(why.contains("check")
                    ? "A downloaded file did not pass its check. Try again."
                    : "The download stopped. Check your connection and try again.")
                pause(packId)
            }
        }
        publish(packId, force: true)
        if running[packId, default: []].isEmpty { pausing.remove(packId) }
    }

    fileprivate func eventsFinished() {
        backgroundCompletion?()
        backgroundCompletion = nil
    }
}

/// The background session's delegate. Runs on the session's own queue;
/// a finished file must be moved before the callback returns, so the
/// file work happens here and the results go to `VoicePacks`.
final class VoiceDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    enum Outcome {
        case verified
        case cancelled
        case retry(String)
    }

    /// "pack/file|mode", where mode is "full", "range:<offset>" or "resume".
    static func describe(_ pack: String, _ file: String, mode: String) -> String { "\(pack)/\(file)|\(mode)" }

    static func parse(_ d: String?) -> (pack: String, file: String, mode: String)? {
        guard let d, let bar = d.firstIndex(of: "|") else { return nil }
        let path = d[..<bar], mode = String(d[d.index(after: bar)...])
        guard let slash = path.firstIndex(of: "/") else { return nil }
        return (String(path[..<slash]), String(path[path.index(after: slash)...]), mode)
    }

    private func file(_ task: URLSessionTask) -> (pack: VoiceCatalog.Pack, file: VoiceCatalog.Pack.File, mode: String)? {
        guard let d = Self.parse(task.taskDescription), let pack = VoiceCatalog.bundled?.pack(d.pack),
              let f = pack.files.first(where: { $0.name == d.file }) else { return nil }
        return (pack, f, d.mode)
    }

    /// Outcomes decided in didFinishDownloading, reported when the task
    /// completes.
    private var outcomes: [Int: Outcome] = [:]
    private let lock = NSLock()

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let (pack, f, _) = file(downloadTask) else { return }
        // A ranged or resumed request reports only what is left as its
        // expected total; what came before is the rest of the file.
        let before = totalBytesExpectedToWrite > 0 ? max(0, f.size - totalBytesExpectedToWrite) : 0
        let bytes = before + totalBytesWritten
        Task { @MainActor in VoicePacks.shared.progress(pack.id, f.name, bytes: bytes) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (pack, f, mode) = file(downloadTask) else { return }
        let outcome = place(location, task: downloadTask, pack: pack, file: f, mode: mode)
        lock.lock()
        outcomes[downloadTask.taskIdentifier] = outcome
        lock.unlock()
    }

    /// Moves the downloaded bytes into the `.part` file, then checks the
    /// whole file and gives it its own name if it passes.
    private func place(_ location: URL, task: URLSessionDownloadTask, pack: VoiceCatalog.Pack,
                       file f: VoiceCatalog.Pack.File, mode: String) -> Outcome {
        let fm = FileManager.default
        guard let dir = try? VoicePackFiles.prepare(pack.id) else { return .retry("could not be saved") }
        let part = VoicePackFiles.partURL(f, in: dir)
        let http = task.response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if mode.hasPrefix("range:"), status == 206 {
            // The rest of the file: add it to what is there, if the
            // server sent it from where the part file ends.
            let offset = Int64(mode.dropFirst("range:".count)) ?? -1
            let range = http?.value(forHTTPHeaderField: "Content-Range") ?? ""
            let start = Int64(range.split(separator: " ").last?.split(separator: "-").first ?? "") ?? -1
            guard offset == VoicePackFiles.size(part), start == offset,
                  let out = try? FileHandle(forWritingTo: part), let input = try? FileHandle(forReadingFrom: location) else {
                try? fm.removeItem(at: part)
                return .retry("could not be resumed")
            }
            out.seekToEndOfFile()
            while true {
                let chunk: Data = autoreleasepool { input.readData(ofLength: 1 << 20) }
                if chunk.isEmpty { break }
                out.write(chunk)
            }
            try? out.close()
            try? input.close()
        } else if status == 200 || (mode == "resume" && status == 206) {
            // The whole file: a fresh download, or one URLSession resumed
            // and put back together itself.
            try? fm.removeItem(at: part)
            do { try fm.moveItem(at: location, to: part) } catch { return .retry("could not be saved") }
        } else {
            return .retry("answered HTTP \(status)")
        }
        switch VoicePackFiles.verify(part, against: f) {
        case .ok:
            let final = dir.appendingPathComponent(f.name)
            try? fm.removeItem(at: final)
            do { try fm.moveItem(at: part, to: final) } catch { return .retry("could not be saved") }
            return .verified
        case let .wrongSize(s) where s < f.size:
            return .retry("arrived incomplete")
        default:
            try? fm.removeItem(at: part)
            return .retry("did not pass its size and sha256 check")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let (pack, f, _) = file(task) else { return }
        lock.lock()
        var outcome = outcomes.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        if let error = error as NSError? {
            // Keep what arrived, to resume from.
            if let data = error.userInfo[NSURLSessionDownloadTaskResumeData] as? Data,
               let dir = try? VoicePackFiles.prepare(pack.id) {
                try? data.write(to: VoicePackFiles.resumeURL(f, in: dir))
            }
            outcome = error.code == NSURLErrorCancelled ? .cancelled : .retry("stopped: \(error.localizedDescription)")
        }
        let result = outcome ?? .retry("ended without a file")
        Task { @MainActor in VoicePacks.shared.fileDone(pack.id, f.name, outcome: result) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in VoicePacks.shared.eventsFinished() }
    }
}
