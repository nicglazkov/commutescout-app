import CryptoKit
import XCTest

/// Download verification: sizes and hashes, the installed marker, and
/// what a damaged pack loses.
final class VoicePackFilesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("voices-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private let a = Data("model bytes ".utf8) + Data(repeating: 7, count: 3000)
    private let b = Data("tokens\n".utf8)

    private func hex(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    /// A two-file pack with the real hashes of `a` and `b`.
    private func pack() throws -> VoiceCatalog.Pack {
        let json = """
        {"schema":1,"release":"t","default_pack":"p","packs":[{"id":"p","title":"Test voices","engine":"kokoro",
        "engine_version":"Kokoro v1.0","sample_rate":24000,"text_input":"normalized","generation":{"speed":1.0},
        "license":{"spdx":"Apache-2.0","name":"Apache License 2.0","url":"https://example.com"},"attribution":"x",
        "voices":[],"download_size":\(a.count + b.count),"files":[
        {"name":"model.int8.onnx","role":"model","url":"https://example.com/p.model.int8.onnx","sha256":"\(hex(a))","size":\(a.count)},
        {"name":"tokens.txt","role":"tokens","url":"https://example.com/p.tokens.txt","sha256":"\(hex(b))","size":\(b.count)}]}]}
        """
        return try XCTUnwrap(VoiceCatalog.decode(Data(json.utf8)).packs.first)
    }

    private func write(_ d: Data, _ name: String) throws -> URL {
        let dir = try VoicePackFiles.prepare("p", root: root)
        let u = dir.appendingPathComponent(name)
        try d.write(to: u)
        return u
    }

    func testSha256MatchesCryptoKit() throws {
        let u = try write(a, "x")
        XCTAssertEqual(VoicePackFiles.sha256(u), hex(a))
    }

    func testVerifyChecksSizeThenHash() throws {
        let p = try pack()
        let model = p.files[0]
        XCTAssertEqual(VoicePackFiles.verify(root.appendingPathComponent("nothing"), against: model), .missing)
        XCTAssertEqual(VoicePackFiles.verify(try write(a, "good"), against: model), .ok)
        XCTAssertEqual(VoicePackFiles.verify(try write(a.prefix(100), "short"), against: model), .wrongSize(100))
        var flipped = a
        flipped[5] ^= 0xFF
        XCTAssertEqual(VoicePackFiles.verify(try write(flipped, "bad"), against: model), .wrongHash)
    }

    func testAPackIsInstalledOnlyWithItsMarkerAndEveryFileTheRightSize() throws {
        let p = try pack()
        _ = try write(a, "model.int8.onnx")
        XCTAssertFalse(VoicePackFiles.markInstalledIfComplete(p, root: root), "a file is missing")
        XCTAssertFalse(VoicePackFiles.installedAndIntact(p, root: root))
        _ = try write(b, "tokens.txt")
        XCTAssertFalse(VoicePackFiles.installedAndIntact(p, root: root), "no marker yet")
        XCTAssertTrue(VoicePackFiles.markInstalledIfComplete(p, root: root))
        XCTAssertTrue(VoicePackFiles.installedAndIntact(p, root: root))
    }

    func testADamagedPackLosesItsMarkerAndOnlyTheBadFiles() throws {
        let p = try pack()
        _ = try write(a, "model.int8.onnx")
        _ = try write(b, "tokens.txt")
        XCTAssertTrue(VoicePackFiles.markInstalledIfComplete(p, root: root))
        _ = try write(a.prefix(10), "model.int8.onnx")   // truncated on disk
        XCTAssertFalse(VoicePackFiles.installedAndIntact(p, root: root))
        XCTAssertEqual(VoicePackFiles.unmarkBroken(p, root: root), ["model.int8.onnx"])
        let dir = VoicePackFiles.directory("p", root: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(VoicePackFiles.marker).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("model.int8.onnx").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("tokens.txt").path))
    }

    func testBytesOnDiskCountsPartialFilesAndSpaceNeededAddsTenPercent() throws {
        let p = try pack()
        _ = try write(b, "tokens.txt")
        _ = try write(a.prefix(1000), "model.int8.onnx.part")
        XCTAssertEqual(VoicePackFiles.bytesOnDisk(p, root: root), Int64(b.count + 1000))
        let left = Int64(a.count - 1000)
        XCTAssertEqual(VoicePackFiles.neededBytes(p, root: root), left + left / 10)
        XCTAssertTrue(VoicePackFiles.hasAnything("p", root: root))
        VoicePackFiles.remove("p", root: root)
        XCTAssertFalse(VoicePackFiles.hasAnything("p", root: root))
    }

    func testANewReleaseDropsRenamedFilesAndKeepsCurrentOnesAndParts() throws {
        let p = try pack()
        _ = try write(b, "tokens.txt")
        _ = try write(a.prefix(1000), "model.int8.onnx.part")
        _ = try write(a, "model.old.onnx")   // what the previous catalog named the model
        XCTAssertEqual(VoicePackFiles.removeStale(p, root: root), ["model.old.onnx"])
        let dir = VoicePackFiles.directory("p", root: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("tokens.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("model.int8.onnx.part").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("model.old.onnx").path))
    }

    func testThePackFolderIsExcludedFromBackup() throws {
        let dir = try VoicePackFiles.prepare("p", root: root)
        XCTAssertEqual(try dir.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }
}
