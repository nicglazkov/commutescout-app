import CryptoKit
import Foundation

/// Where voice packs live on the phone and how a pack's files are
/// checked. A pack is in `Application Support/voices/<pack id>/`,
/// excluded from iCloud backup. A file is downloaded to `<name>.part`,
/// checked against the catalog's size and sha256, and only then renamed
/// to its own name. When every file has passed, `pack.ok` is written,
/// and only a pack with that marker counts as installed (docs/voices.md).
enum VoicePackFiles {
    static let marker = "pack.ok"

    /// `Application Support/voices`, made on first use and kept out of
    /// backups: the files are large and can be downloaded again.
    static var root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("voices", isDirectory: true)
    }()

    static func directory(_ packId: String, root: URL = root) -> URL {
        root.appendingPathComponent(packId, isDirectory: true)
    }

    static func partURL(_ file: VoiceCatalog.Pack.File, in dir: URL) -> URL {
        dir.appendingPathComponent(file.name + ".part")
    }

    static func resumeURL(_ file: VoiceCatalog.Pack.File, in dir: URL) -> URL {
        dir.appendingPathComponent(file.name + ".resume")
    }

    /// Makes the pack's directory and marks it, and the voices folder
    /// above it, as excluded from backup.
    @discardableResult
    static func prepare(_ packId: String, root: URL = root) throws -> URL {
        let dir = directory(packId, root: root)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var r = root, d = dir
        try? r.setResourceValues(values)
        try? d.setResourceValues(values)
        return dir
    }

    static func size(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    /// The sha256 of a file as lowercase hex, read in 1 MB pieces so a
    /// 100 MB model never sits in memory whole.
    static func sha256(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while true {
            let chunk: Data? = autoreleasepool { h.readData(ofLength: 1 << 20) }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    enum Check: Equatable {
        case ok
        case missing
        case wrongSize(Int64)
        case wrongHash
    }

    /// A downloaded file against the catalog: size first, which is
    /// cheap, then the hash.
    static func verify(_ url: URL, against file: VoiceCatalog.Pack.File) -> Check {
        guard let s = size(url) else { return .missing }
        guard s == file.size else { return .wrongSize(s) }
        return sha256(url)?.lowercased() == file.sha256.lowercased() ? .ok : .wrongHash
    }

    /// The pack is installed: the marker is there and every file has
    /// the size the catalog says. Hashes were checked when the files
    /// arrived; sizes are checked again here, on every launch and before
    /// the engine loads, which catches a truncated or missing file.
    static func installedAndIntact(_ pack: VoiceCatalog.Pack, root: URL = root) -> Bool {
        let dir = directory(pack.id, root: root)
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent(marker).path) else { return false }
        return brokenFiles(pack, root: root).isEmpty
    }

    /// Files of a pack that are missing or the wrong size.
    static func brokenFiles(_ pack: VoiceCatalog.Pack, root: URL = root) -> [VoiceCatalog.Pack.File] {
        let dir = directory(pack.id, root: root)
        return pack.files.filter { size(dir.appendingPathComponent($0.name)) != $0.size }
    }

    /// Bytes of the pack already on the phone: finished files and
    /// partial ones.
    static func bytesOnDisk(_ pack: VoiceCatalog.Pack, root: URL = root) -> Int64 {
        let dir = directory(pack.id, root: root)
        return pack.files.reduce(0) { sum, f in
            let done = size(dir.appendingPathComponent(f.name)) == f.size ? f.size : 0
            return sum + (done > 0 ? done : min(size(partURL(f, in: dir)) ?? 0, f.size))
        }
    }

    /// Whether any part of the pack is on the phone, finished or not.
    static func hasAnything(_ packId: String, root: URL = root) -> Bool {
        let dir = directory(packId, root: root)
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).contains { $0 != ".DS_Store" }
    }

    /// Writes the marker once every file is in place and the right size.
    @discardableResult
    static func markInstalledIfComplete(_ pack: VoiceCatalog.Pack, root: URL = root) -> Bool {
        guard brokenFiles(pack, root: root).isEmpty else { return false }
        let ok = directory(pack.id, root: root).appendingPathComponent(marker)
        return FileManager.default.createFile(atPath: ok.path, contents: Data("1\n".utf8))
    }

    /// Takes the marker away from a pack whose files no longer match,
    /// and deletes the files that are wrong so a new download replaces
    /// them. Files that are fine are kept.
    static func unmarkBroken(_ pack: VoiceCatalog.Pack, root: URL = root) -> [String] {
        let dir = directory(pack.id, root: root)
        let broken = brokenFiles(pack, root: root)
        guard !broken.isEmpty else { return [] }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(marker))
        for f in broken { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f.name)) }
        return broken.map(\.name)
    }

    /// Deletes what an earlier catalog had in the pack's folder and this
    /// one does not, such as a model file a new release renamed. Parts
    /// and resume data of current files stay.
    @discardableResult
    static func removeStale(_ pack: VoiceCatalog.Pack, root: URL = root) -> [String] {
        let dir = directory(pack.id, root: root)
        var keep: Set<String> = [marker]
        for f in pack.files {
            keep.insert(f.name)
            keep.insert(partURL(f, in: dir).lastPathComponent)
            keep.insert(resumeURL(f, in: dir).lastPathComponent)
        }
        let stale = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !keep.contains($0) }
        for name in stale { try? FileManager.default.removeItem(at: dir.appendingPathComponent(name)) }
        return stale
    }

    static func remove(_ packId: String, root: URL = root) {
        try? FileManager.default.removeItem(at: directory(packId, root: root))
    }

    /// Room for what is left to download plus 10%.
    static func neededBytes(_ pack: VoiceCatalog.Pack, root: URL = root) -> Int64 {
        let left = max(0, pack.downloadSize - bytesOnDisk(pack, root: root))
        return left + left / 10
    }

    static func freeBytes() -> Int64? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let v = try? (FileManager.default.fileExists(atPath: base.path) ? base : home)
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage
    }

    /// "145 MB".
    /// "34%", for a download's progress.
    static func percent(_ done: Int64, _ total: Int64) -> String {
        "\(total > 0 ? Int(Double(done) / Double(total) * 100) : 0)%"
    }

    static func label(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
