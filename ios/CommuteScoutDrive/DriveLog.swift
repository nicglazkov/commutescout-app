import Foundation

/// A small on-device log of what the app did on a drive: routes, spoken
/// alerts, marker fetches, location gaps, foreground changes. Written to
/// Documents/drive.log (capped, rotated once) so it can be pulled from a
/// paired phone without touching the screen. Also mirrored to the
/// console in debug builds.
enum DriveLog {
    private static let queue = DispatchQueue(label: "cs.drivelog")
    private static let cap = 1_500_000
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = .current
        return f
    }()

    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("drive.log")
    }

    static func note(_ message: String) {
        let line = "\(stamp.string(from: Date())) \(message)\n"
        #if DEBUG
        NSLog("CS %@", message)
        #endif
        queue.async {
            let u = url
            if let attrs = try? FileManager.default.attributesOfItem(atPath: u.path),
               let size = attrs[.size] as? Int, size > cap {
                let old = u.deletingLastPathComponent().appendingPathComponent("drive.1.log")
                try? FileManager.default.removeItem(at: old)
                try? FileManager.default.moveItem(at: u, to: old)
            }
            if let h = try? FileHandle(forWritingTo: u) {
                h.seekToEndOfFile()
                h.write(line.data(using: .utf8)!)
                try? h.close()
            } else {
                try? line.write(to: u, atomically: true, encoding: .utf8)
            }
        }
    }

    static func meters(_ m: Double) -> String {
        m >= 1000 ? String(format: "%.1f km", m / 1000) : String(format: "%.0f m", m)
    }
}
