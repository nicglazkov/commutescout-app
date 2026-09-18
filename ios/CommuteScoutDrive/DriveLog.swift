import Foundation

/// A small on-device log of what the app did on a drive: routes, spoken
/// alerts, marker fetches, location gaps, foreground changes. Written to
/// Library/Caches/drive.log (capped, rotated once, excluded from backups)
/// so it can be pulled from a paired phone without touching the screen,
/// in every build. Also mirrored to the console in debug builds.
enum DriveLog {
    private static let queue = DispatchQueue(label: "cs.drivelog")
    private static let cap = 1_500_000
    private static var excluded = false
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = .current
        return f
    }()

    static var url: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("drive.log")
    }

    /// Marks the log and its rotated copy as not for backup. Runs on the
    /// log queue after the first write and again after each rotation.
    private static func excludeFromBackup(_ files: [URL]) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        for f in files where FileManager.default.fileExists(atPath: f.path) {
            var u = f
            try? u.setResourceValues(values)
        }
    }

    static func note(_ message: String) {
        let line = "\(stamp.string(from: Date())) \(message)\n"
        #if DEBUG
        NSLog("CS %@", message)
        #endif
        queue.async {
            let u = url
            let old = u.deletingLastPathComponent().appendingPathComponent("drive.1.log")
            var rotated = false
            if let attrs = try? FileManager.default.attributesOfItem(atPath: u.path),
               let size = attrs[.size] as? Int, size > cap {
                try? FileManager.default.removeItem(at: old)
                try? FileManager.default.moveItem(at: u, to: old)
                rotated = true
            }
            if let h = try? FileHandle(forWritingTo: u) {
                h.seekToEndOfFile()
                h.write(line.data(using: .utf8)!)
                try? h.close()
            } else {
                try? line.write(to: u, atomically: true, encoding: .utf8)
                rotated = true   // a new file: mark it too
            }
            if rotated || !excluded {
                excludeFromBackup([u, old])
                excluded = true
            }
        }
    }

    static func meters(_ m: Double) -> String {
        m >= 1000 ? String(format: "%.1f km", m / 1000) : String(format: "%.0f m", m)
    }
}
