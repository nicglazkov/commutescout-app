import Foundation

/// The words for a watch alert whose event is over: the capsule at the
/// top, the box in the sheet, and what the alert said.
struct WatchClearedText: Equatable {
    var capsule: String
    var since: String
    var heading: String
    var detail: String
    var said: String

    static func make(_ ref: AlertRef, clearedAt: Date?, now: Date = Date()) -> WatchClearedText {
        let kind = DGKind(markerKind: ref.kind, title: ref.title)
        let noun = SystemNotes.noun(kind)
        let since = clearedAt.map { "Cleared " + EventContent.ago($0, now: now) } ?? "Cleared"
        let lanes = ref.laneLayout != nil ? " All lanes are open." : ""
        // The alert's own time, unless this push is the follow-up (its
        // time is when the clear was sent, not what the alert said).
        let said = !ref.isCleared ? ref.sentAt.map { "What your alert said at " + $0.formatted(date: .omitted, time: .shortened) } : nil
        return WatchClearedText(
            capsule: ref.title.map { "The " + lowerFirst($0) + " is over" } ?? "The \(noun) is over",
            since: since,
            heading: "This \(noun) has cleared",
            detail: since + "." + lanes,
            said: said ?? "What your alert said")
    }

    /// "Crash on US-101" to "crash on US-101", but "US-101 S" stays.
    static func lowerFirst(_ s: String) -> String {
        guard let f = s.first, s.count > 1, s.dropFirst().first?.isLowercase == true else { return s }
        return f.lowercased() + s.dropFirst()
    }
}
