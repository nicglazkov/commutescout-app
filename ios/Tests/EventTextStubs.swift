import Foundation

/// The test target compiles the event files on their own; this stands in
/// for the app's unit formatting, which lives with the app's settings.
enum Units {
    static func temperature(celsius: Double) -> String { "\(Int(celsius.rounded()))\u{00B0}C" }
    static func windDirection(_ degrees: Double) -> String { String(Int(degrees)) }
}
