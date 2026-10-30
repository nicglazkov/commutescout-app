import Foundation

/// The lanes at an event, as the server sends them in `lane_layout`.
/// Lanes run left to right; lane 1 is the leftmost.
///
/// Decoding never fails: a field that is missing or the wrong shape is
/// left out, so a bad layout can never drop the marker it rides on. A
/// layout with no usable lanes draws as the kind's own picture.
struct LaneLayout: Decodable, Hashable {
    enum LaneType: String, Hashable { case general, hov, express, exit, aux }

    struct Lane: Hashable {
        var n: Int
        var type: LaneType = .general
        var closed: Bool = false
    }

    var total: Int = 0
    var lanes: [Lane] = []
    var leftShoulderClosed = false
    var rightShoulderClosed = false
    /// The lane to move to, 1-based, when the source says.
    var target: Int?
    /// "feed", "count_only" or "lookup".
    var basis: String?

    init(total: Int, lanes: [Lane], leftShoulderClosed: Bool = false, rightShoulderClosed: Bool = false,
         target: Int? = nil, basis: String? = nil) {
        self.total = total
        self.lanes = lanes
        self.leftShoulderClosed = leftShoulderClosed
        self.rightShoulderClosed = rightShoulderClosed
        self.target = target
        self.basis = basis
    }

    private enum K: String, CodingKey { case total, lanes, shoulder, target, basis }
    private enum LK: String, CodingKey { case n, type, state }
    private enum SK: String, CodingKey { case left, right }

    init(from decoder: Decoder) {
        guard let c = try? decoder.container(keyedBy: K.self) else { return }
        basis = (try? c.decodeIfPresent(String.self, forKey: .basis)) ?? nil
        target = (try? c.decodeIfPresent(Int.self, forKey: .target)) ?? nil
        if var arr = try? c.nestedUnkeyedContainer(forKey: .lanes) {
            var out: [Lane] = []
            while !arr.isAtEnd {
                guard let l = try? arr.nestedContainer(keyedBy: LK.self) else {
                    _ = try? arr.decode(Skip.self)
                    continue
                }
                guard let n = (try? l.decodeIfPresent(Int.self, forKey: .n)) ?? nil else { continue }
                let type = ((try? l.decodeIfPresent(String.self, forKey: .type)) ?? nil).flatMap(LaneType.init(rawValue:))
                let state = (try? l.decodeIfPresent(String.self, forKey: .state)) ?? nil
                out.append(Lane(n: n, type: type ?? .general, closed: state == "closed"))
            }
            lanes = out.sorted { $0.n < $1.n }
        }
        let t = (try? c.decodeIfPresent(Int.self, forKey: .total)) ?? nil
        total = max(t ?? 0, lanes.map(\.n).max() ?? 0)
        // Lanes the source left out are open general lanes.
        if total > 0, total <= 12, lanes.count < total {
            let have = Set(lanes.map(\.n))
            lanes = (lanes + (1 ... total).filter { !have.contains($0) }.map { Lane(n: $0) }).sorted { $0.n < $1.n }
        }
        if let s = try? c.nestedContainer(keyedBy: SK.self, forKey: .shoulder) {
            leftShoulderClosed = ((try? s.decodeIfPresent(String.self, forKey: .left)) ?? nil) == "closed"
            rightShoulderClosed = ((try? s.decodeIfPresent(String.self, forKey: .right)) ?? nil) == "closed"
        }
    }

    /// Swallows one array element of any shape.
    private struct Skip: Decodable { init(from _: Decoder) {} }

    /// Enough to draw: between 1 and 12 lanes.
    var isUsable: Bool { total >= 1 && total <= 12 && lanes.count == total }
    var closedLanes: [Int] { lanes.filter(\.closed).map(\.n) }
    var anyLaneClosed: Bool { !closedLanes.isEmpty }
}

/// What the lane drawing shows for a layout: where you are, where to go
/// and the closed lanes, in drawing indices (0 is the leftmost lane).
struct LanePlan: Equatable {
    var count: Int
    var closed: [Int]            // 0-based
    var tinted: [Int]            // HOV and express lanes
    var from: Int                // the lane the arrow starts in
    var to: Int                  // the lane it ends in
    var shoulderLeft: Bool
    var shoulderRight: Bool

    var moves: Int { to - from }

    init?(_ layout: LaneLayout?) {
        guard let layout, layout.isUsable else { return nil }
        count = layout.total
        closed = layout.closedLanes.map { $0 - 1 }
        tinted = layout.lanes.filter { $0.type == .hov || $0.type == .express }.map { $0.n - 1 }
        shoulderLeft = layout.leftShoulderClosed
        shoulderRight = layout.rightShoulderClosed
        let shutLanes = closed
        let open = (0 ..< count).filter { !shutLanes.contains($0) }
        if closed.isEmpty || open.isEmpty {
            // Only shoulders closed, or everything is: no merge arrow.
            let mid = count / 2
            from = min(max(0, (layout.target ?? (mid + 1)) - 1), count - 1)
            to = from
            return
        }
        // You start in the closed lane at the edge the closure grows
        // from: the right edge when the closure touches it, else the left.
        let shut = closed, n = count
        let rightSide = shut.contains(n - 1) || (shut.first ?? 0) >= n / 2
        let start = rightSide ? shut.max()! : shut.min()!
        from = start
        if let t = layout.target, t >= 1, t <= n, !shut.contains(t - 1) {
            to = t - 1
        } else {
            to = open.min { abs($0 - start) < abs($1 - start) } ?? start
        }
    }

    /// "Move one lane left.", or nil when there is nothing to do.
    var instruction: String? {
        guard moves != 0 else { return nil }
        let words = ["zero", "one", "two", "three", "four", "five", "six"]
        let k = abs(moves)
        let n = k < words.count ? words[k] : "\(k)"
        return "Move \(n) lane\(k == 1 ? "" : "s") \(moves < 0 ? "left" : "right")."
    }
}

/// The rule for "has cleared": an event on the route ahead, near enough
/// to have been shown, that a successful fetch no longer returns before
/// the driver reaches it. Passing an event says nothing.
enum ClearingRule {
    struct Seen: Equatable { let key: String; let along: Double }

    /// Keys that vanished ahead of the driver, nearest first.
    static func vanished(previous: [Seen], now: Set<String>, here: Double, within: Double) -> [String] {
        previous
            .filter { !now.contains($0.key) && $0.along > here + 30 && $0.along - here <= within }
            .sorted { $0.along < $1.along }
            .map(\.key)
    }

    /// How close two reports of one kind sit to be one event, in degrees
    /// (about 55 m).
    static let samePlace = 0.0005

    /// A marker with no id is keyed by its words too, so a new label
    /// reads as a new key. The same kind in the same place is the same
    /// event, not one that cleared.
    static func stillReported(_ m: RoadMarker, among now: [RoadMarker]) -> Bool {
        guard m.id == nil else { return false }
        return now.contains { $0.kind == m.kind && abs($0.lat - m.lat) <= samePlace && abs($0.lon - m.lon) <= samePlace }
    }

    /// Whether a clearing is said out loud: the alert's own rule, which
    /// already holds the voice setting, the plugin setting and the
    /// per-kind choices, unless the driver muted alerts. Only on a route.
    static func speaks(ruleSpeaks: Bool, muted: Bool, onRoute: Bool) -> Bool {
        ruleSpeaks && !muted && onRoute
    }
}
