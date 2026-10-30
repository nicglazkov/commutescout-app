import AVFoundation
import CryptoKit
import SwiftUI

/// The bottom of Settings > Voice: each set of CommuteScout voices that
/// is on the phone or on its way, with its progress, and Cancel, Resume
/// or Delete. Voices are picked in the list above; picking one that is
/// not downloaded starts its set here.
struct VoicePackSection: View {
    @ObservedObject private var packs = VoicePacks.shared
    @ObservedObject private var connectivity = Connectivity.shared
    @ObservedObject var previews: VoicePreviewPlayer
    /// The voice id that is picked.
    let picked: String
    let pick: (String) -> Void

    @State private var askDelete: VoiceCatalog.Pack?

    private var shown: [VoiceCatalog.Pack] {
        (packs.catalog?.offeredPacks() ?? []).filter { packs.state($0.id) != .none }
    }

    var body: some View {
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                DGSectionLabel("Downloaded voices")
                DGGroup {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, pack in
                        if i > 0 { DGDivider(inset: 14) }
                        packRow(pack).padding(.horizontal, 14).padding(.vertical, 10)
                    }
                }
                DGFootnote("One download adds every voice in a set. When a trip starts, the first instructions may be said in the system voice while the rest are prepared.")
            }
            .confirmationDialog("Delete \(askDelete?.title.lowercased() ?? "voices")?", isPresented: Binding(get: { askDelete != nil }, set: { if !$0 { askDelete = nil } }),
                                titleVisibility: .visible, presenting: askDelete) { pack in
                Button("Delete \(VoicePackFiles.label(pack.downloadSize))", role: .destructive) { delete(pack) }
                Button("Cancel", role: .cancel) {}
            } message: { pack in
                Text("This frees \(VoicePackFiles.label(max(VoicePackFiles.bytesOnDisk(pack), 0))) on this phone. You can download \(pack.title.lowercased()) again at any time.")
            }
        }
    }

    @ViewBuilder
    private func packRow(_ pack: VoiceCatalog.Pack) -> some View {
        let state = packs.state(pack.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.title).font(DG.font(16, .medium)).foregroundStyle(DG.ink)
                    Text(Self.summary(pack)).font(DG.T.rowSub).foregroundStyle(DG.sub)
                }
                Spacer(minLength: 8)
                packAction(pack, state)
            }
            switch state {
            case let .downloading(done, total):
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .accessibilityIdentifier("voices-progress-\(pack.id)")
                Text(progressText(done, total, waiting: !connectivity.onWifi && !cellularAllowed(pack)))
                    .font(DG.T.rowSub.monospacedDigit()).foregroundStyle(DG.sub)
            case let .paused(done, total):
                ProgressView(value: Double(done), total: Double(max(total, 1))).tint(.secondary)
                Text("Paused: \(VoicePackFiles.label(done)) of \(VoicePackFiles.label(total))")
                    .font(DG.T.rowSub.monospacedDigit()).foregroundStyle(DG.sub)
            case let .failed(why):
                Text(why).font(DG.T.rowSub).foregroundStyle(DG.color(.high))
            case .installed, .none:
                EmptyView()
            }
        }
        .padding(.vertical, 2)
    }

    /// The buttons for each state: Cancel while it runs; Resume and
    /// Delete when it stopped; Delete once it is on the phone.
    @ViewBuilder
    private func packAction(_ pack: VoiceCatalog.Pack, _ state: VoicePacks.State) -> some View {
        switch state {
        case .downloading:
            Button("Cancel") { packs.pause(pack.id) }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("voices-cancel-\(pack.id)")
        case .paused, .failed:
            HStack(spacing: 16) {
                Button("Delete", role: .destructive) { askDelete = pack }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("voices-delete-\(pack.id)")
                Button("Resume") { packs.download(pack.id, cellular: cellularAllowed(pack)) }
                    .buttonStyle(.borderless).fontWeight(.semibold)
                    .accessibilityIdentifier("voices-resume-\(pack.id)")
            }
        case .installed:
            Button("Delete", role: .destructive) { askDelete = pack }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("voices-delete-\(pack.id)")
        case .none:
            EmptyView()
        }
    }

    /// "8 voices, US and UK English, 188 MB".
    static func summary(_ pack: VoiceCatalog.Pack) -> String {
        let accents = Set(pack.voices.map { VoicePick.regionCode($0.accent) ?? "" })
        let where_ = accents == ["US"] ? "US English" : accents == ["GB"] ? "UK English" : "US and UK English"
        return "\(pack.voices.count) voices, \(where_), \(VoicePackFiles.label(pack.downloadSize))"
    }

    private func progressText(_ done: Int64, _ total: Int64, waiting: Bool) -> String {
        let base = "\(VoicePackFiles.label(done)) of \(VoicePackFiles.label(total)) (\(VoicePackFiles.percent(done, total)))"
        return waiting ? base + ". Waiting for Wi-Fi." : base
    }

    private func cellularAllowed(_ pack: VoiceCatalog.Pack) -> Bool {
        UserDefaults.standard.bool(forKey: "cs.voices.cellular.\(pack.id)")
    }

    private func delete(_ pack: VoiceCatalog.Pack) {
        // The voice in use goes with its set: back to Automatic.
        if pack.voices.contains(where: { $0.id == picked }) { pick("") }
        previews.stop()
        packs.delete(pack.id)
    }
}

/// Streams a voice's sample clip from the release, so a voice can be
/// heard before its pack is downloaded. One sample at a time.
@MainActor
final class VoicePreviewPlayer: ObservableObject {
    @Published private(set) var playing: String?
    @Published private(set) var loading: String?
    private var player: AVPlayer?
    private var watch: NSKeyValueObservation?
    private var end: NSObjectProtocol?

    func toggle(_ v: VoiceCatalog.Voice) {
        if playing == v.id || loading == v.id { stop(); return }
        play(v)
    }

    private var fetch: URLSessionDataTask?

    /// Where a sample is kept once fetched, so a second tap plays at once.
    private static func cached(_ v: VoiceCatalog.Voice) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("voice-previews")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(v.id).m4a")
    }

    /// Samples are small (about 60 KB). GitHub serves them as
    /// application/octet-stream behind a redirect, which AVPlayer will
    /// not stream, so the sample is fetched, checked against its hash,
    /// and played from the cache.
    func play(_ v: VoiceCatalog.Voice) {
        stop()
        guard let preview = v.preview else { return }
        loading = v.id
        let local = Self.cached(v)
        if VoicePackFiles.size(local) == preview.size { start(v, local); return }
        var req = URLRequest(url: preview.url, timeoutInterval: 15)
        req.allowsExpensiveNetworkAccess = true
        fetch = URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            Task { @MainActor in
                guard let self, self.loading == v.id else { return }
                guard let data, Int64(data.count) == preview.size,
                      SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == preview.sha256,
                      (try? data.write(to: local, options: .atomic)) != nil else {
                    DriveLog.note("voices: sample of \(v.name) failed to load: \(error?.localizedDescription ?? "bad download")")
                    self.stop()
                    return
                }
                self.start(v, local)
            }
        }
        fetch?.resume()
    }

    private func start(_ v: VoiceCatalog.Voice, _ url: URL) {
        SpeechFocus.shared.take()
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        watch = p.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            Task { @MainActor in
                guard let self, self.player === p else { return }
                if p.timeControlStatus == .playing { self.loading = nil; self.playing = v.id }
                if p.currentItem?.status == .failed {
                    DriveLog.note("voices: sample of \(v.name) failed to play: \(p.currentItem?.error?.localizedDescription ?? "unknown")")
                    self.stop()
                }
            }
        }
        end = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        p.play()
    }

    func stop() {
        fetch?.cancel()
        fetch = nil
        player?.pause()
        player = nil
        watch = nil
        if let end { NotificationCenter.default.removeObserver(end) }
        end = nil
        playing = nil
        loading = nil
        if !Voice.synth.isSpeaking, !NeuralSpeaker.shared.busy { SpeechFocus.shared.release() }
    }
}

/// Settings > About > Voice licenses: who made each voice and under
/// what terms, and the licenses of the speech engine in the app.
struct VoiceLicensesView: View {
    @ObservedObject private var packs = VoicePacks.shared

    var body: some View {
        DGPage(title: "Voice licenses", identifier: "page-voice-licenses") {
            VStack(alignment: .leading, spacing: 0) {
                Text("CommuteScout voices run on the sherpa-onnx speech engine with ONNX Runtime. Each set of voices comes from the project named below, under its own license.")
                    .font(DG.font(15)).foregroundStyle(DG.sub).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 6).padding(.top, 8)
                ForEach(packs.catalog?.offeredPacks() ?? []) { pack in
                    DGSectionLabel(pack.title)
                    DGGroup {
                        Text(pack.attribution).font(DG.font(14)).foregroundStyle(DG.ink).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        DGDivider(inset: 14)
                        fact("Model", pack.engineVersion)
                        DGDivider(inset: 14)
                        fact("License", pack.license.name)
                        if let url = URL(string: pack.license.url) {
                            DGDivider(inset: 14)
                            Link(destination: url) {
                                DGRow(title: "License source", chevron: false, leading: { EmptyView() },
                                      trailing: { Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .bold)).foregroundStyle(DG.faint) })
                            }
                            .buttonStyle(DGRowPress())
                        }
                        if packs.state(pack.id) == .installed {
                            ForEach(["NOTICE", "LICENSE"], id: \.self) { name in
                                DGDivider(inset: 14)
                                textLink(name == "NOTICE" ? "Notice" : "License text",
                                         title: "\(pack.title): \(name == "NOTICE" ? "notice" : "license")", text: Self.packText(pack, name))
                            }
                        }
                    }
                    if pack.isSupertonic {
                        DGFootnote("Use of these voices is subject to the use restrictions in Attachment A of the OpenRAIL-M license.")
                    }
                    if packs.state(pack.id) != .installed {
                        DGFootnote("The full license and notice come with the voices and appear here after you download them.")
                    }
                }
                DGSectionLabel("Speech engine")
                DGGroup {
                    textLink("sherpa-onnx, Apache License 2.0", title: "sherpa-onnx", text: Self.bundled("sherpa-onnx-LICENSE"))
                    DGDivider(inset: 14)
                    textLink("ONNX Runtime, MIT License", title: "ONNX Runtime", text: Self.bundled("onnxruntime-LICENSE"))
                }
            }
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        DGRow(title: title, value: value, chevron: false) { EmptyView() }
    }

    private func textLink(_ row: String, title: String, text: String) -> some View {
        NavigationLink { LicenseTextView(title: title, text: text) } label: { DGRow(title: row) { EmptyView() } }
            .buttonStyle(DGRowPress())
    }

    static func packText(_ pack: VoiceCatalog.Pack, _ name: String) -> String {
        let url = VoicePackFiles.directory(pack.id).appendingPathComponent(name)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "The file is missing. Download the voices again to restore it."
    }

    static func bundled(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }
}

struct LicenseTextView: View {
    let title: String
    let text: String

    var body: some View {
        DGPage(title: title, identifier: "page-license-text") {
            Text(text)
                .font(.system(.footnote, design: .monospaced)).foregroundStyle(DG.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
    }
}
