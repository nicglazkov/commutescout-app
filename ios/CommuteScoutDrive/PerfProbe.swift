import Foundation
import QuartzCore

/// Battery measurement aid for debug builds (docs/battery.md).
///
/// Launched with `-csPerf`, the app counts what costs power: map frames
/// drawn (every Metal drawable the map takes), location fixes, map view
/// redraws of the SwiftUI tree, marker rebuilds and app network calls,
/// and prints one `CSPERF` line every 10 seconds. Without the argument
/// nothing is counted and nothing runs. Release builds do not have it.
enum PerfProbe {
    #if DEBUG
    static let on = ProcessInfo.processInfo.arguments.contains("-csPerf")
    private static let lock = NSLock()
    private static var counts: [String: Int] = [:]
    private static var timer: Timer?
    private static var since = Date()

    static func count(_ key: String, _ n: Int = 1) {
        guard on else { return }
        lock.lock()
        counts[key, default: 0] += n
        lock.unlock()
    }

    @MainActor static func start() {
        guard on, timer == nil else { return }
        swizzleDrawables()
        since = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in flush() }
    }

    private static func flush() {
        lock.lock()
        let c = counts
        counts = [:]
        lock.unlock()
        let secs = Date().timeIntervalSince(since)
        since = Date()
        let parts = c.keys.sorted().map { "\($0)=\(c[$0] ?? 0)" }.joined(separator: " ")
        NSLog("CSPERF secs=%.1f %@", secs, parts)
    }

    /// Every frame the map renders takes one drawable from its Metal
    /// layer; nothing else in the app draws with Metal.
    private static func swizzleDrawables() {
        guard let a = class_getInstanceMethod(CAMetalLayer.self, #selector(CAMetalLayer.nextDrawable)),
              let b = class_getInstanceMethod(CAMetalLayer.self, #selector(CAMetalLayer.cs_countedNextDrawable)) else { return }
        method_exchangeImplementations(a, b)
    }
    #else
    @inline(__always) static func count(_: String, _: Int = 1) {}
    @MainActor static func start() {}
    #endif
}

#if DEBUG
extension CAMetalLayer {
    @objc dynamic func cs_countedNextDrawable() -> CAMetalDrawable? {
        PerfProbe.count("frames")
        return cs_countedNextDrawable()   // the original, after the swap
    }
}
#endif
