import CoreGraphics
import Foundation

// The trip screen's arithmetic, apart from any view: where marks sit on
// the ahead line, and what a trip changed mid-drive routes through.

/// The ahead line runs from the driver (bottom) to the destination
/// (top). Distance is drawn on a square-root scale, so the next mile
/// gets most of the room, and marks never crowd each other or the ends.
enum RailLayout {
    struct Slot: Equatable {
        let index: Int
        let y: CGFloat
    }

    /// `gaps` are metres ahead, nearest first; `total` is metres to the
    /// destination; `span` is the track's length. Returns each kept
    /// mark's distance from the top of the track. Marks past the
    /// destination or with no room left are dropped.
    static func slots(gaps: [Double], total: Double, span: CGFloat, minGap: CGFloat = 60, max: Int = 3) -> [Slot] {
        guard total > 0, span >= minGap * 2 else { return [] }
        var out: [Slot] = []
        var floor = span - minGap
        for (i, g) in gaps.enumerated() {
            if out.count >= max || g < 0 || g >= total { continue }
            let y = min(span - CGFloat((g / total).squareRoot()) * span, floor)
            if y < minGap { break }
            out.append(Slot(index: i, y: y))
            floor = y - minGap
        }
        return out
    }
}

/// A trip changed mid-drive: a stop on the way, or somewhere else to go.
enum TripPlan {
    /// The places to route through, in order: the stops already
    /// planned, the new one, then the destination.
    static func through<T>(stops: [T], add: T?, destination: T, same: (T, T) -> Bool) -> [T] {
        var via = stops.filter { !same($0, destination) }
        if let add, !same(add, destination), !via.contains(where: { same($0, add) }) { via.append(add) }
        return via + [destination]
    }

    /// What the change costs, for the bar that offers it.
    static func cost(_ addedSeconds: Double?) -> String? {
        guard let s = addedSeconds else { return nil }
        let min = Int((abs(s) / 60).rounded())
        if min == 0 { return "No extra time" }
        return s > 0 ? "+\(min) min" : "\(min) min faster"
    }

    /// "Peet's Coffee, then SJC Airport".
    static func line(stops: [String], destination: String) -> String {
        stops.isEmpty ? destination : stops.joined(separator: ", ") + ", then " + destination
    }

    /// How many of the planned stops are still ahead, given the
    /// waypoints the trip has left (the destination is one).
    static func stopsLeft(planned: Int, remainingWaypoints: Int) -> Int {
        Swift.max(0, Swift.min(planned, remainingWaypoints - 1))
    }
}
