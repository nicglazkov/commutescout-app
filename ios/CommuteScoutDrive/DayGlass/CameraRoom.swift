import Foundation
import QuartzCore

/// The room the map leaves for an alert tucked under the maneuver card.
/// The puck sits lower by that much so the road ahead still shows below
/// the stacked cards, and moves back when the alert leaves. The numbers
/// are the mockup's: 84 points tucked, 104 open.
enum CameraRoom {
    static let tucked: CGFloat = 84
    static let open: CGFloat = 104
    /// The mockup's ease-out move, in seconds.
    static let duration: CFTimeInterval = 0.9

    /// How much room to make: none off a trip or with no alert showing.
    static func target(navigating: Bool, alertShown: Bool, opened: Bool) -> CGFloat {
        guard navigating, alertShown else { return 0 }
        return opened ? open : tucked
    }

    /// Ferrostar's portrait inset puts the puck in the middle of the
    /// bottom `minHeight` points. With no alert the puck sits where the
    /// mockup has it, about seven tenths down; room moves it down by as
    /// much, keeping it above the trip bar.
    static let baseMinHeight: CGFloat = 418

    static func minHeight(room: CGFloat) -> CGFloat { max(160, baseMinHeight - 2 * room) }

    /// cubic-bezier(.16, 1, .3, 1), the mockup's ease-out.
    static func ease(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        let p1x = 0.16, p1y = 1.0, p2x = 0.3, p2y = 1.0
        func bx(_ s: Double) -> Double { 3 * (1 - s) * (1 - s) * s * p1x + 3 * (1 - s) * s * s * p2x + s * s * s }
        func by(_ s: Double) -> Double { 3 * (1 - s) * (1 - s) * s * p1y + 3 * (1 - s) * s * s * p2y + s * s * s }
        var lo = 0.0, hi = 1.0, s = x
        for _ in 0 ..< 30 {
            s = (lo + hi) / 2
            if bx(s) < x { lo = s } else { hi = s }
        }
        return by(s)
    }
}

/// Moves the room frame by frame, since the map's inset is set without
/// animation on every update.
@MainActor
final class CameraRoomAnimator: NSObject, ObservableObject {
    @Published private(set) var value: CGFloat = 0
    private var from: CGFloat = 0
    private var to: CGFloat = 0
    private var start: CFTimeInterval = 0
    private var link: CADisplayLink?

    func go(to target: CGFloat) {
        guard target != to else { return }
        from = value; to = target; start = CACurrentMediaTime()
        if link == nil {
            let l = CADisplayLink(target: self, selector: #selector(step))
            l.add(to: .main, forMode: .common)
            link = l
        }
    }

    @objc private func step() {
        let t = (CACurrentMediaTime() - start) / CameraRoom.duration
        value = from + (to - from) * CGFloat(CameraRoom.ease(t))
        if t >= 1 {
            value = to
            link?.invalidate(); link = nil
        }
    }
}
