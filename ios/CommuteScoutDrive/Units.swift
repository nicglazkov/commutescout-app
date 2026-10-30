import Foundation

/// Distance units follow the device locale until chosen in Settings,
/// the same rule as the website.
enum Units {
    static var useMiles: Bool {
        get {
            if let v = UserDefaults.standard.string(forKey: "cs.units"), !v.isEmpty { return v == "mi" }
            return Locale.current.measurementSystem == .us
        }
        set { UserDefaults.standard.set(newValue ? "mi" : "km", forKey: "cs.units") }
    }

    static func distance(_ meters: Double) -> String {
        if useMiles {
            let mi = meters / 1609.344
            if mi < 0.2 { return "\(Int((meters * 3.28084 / 50).rounded() * 50)) ft" }
            return mi < 10 ? String(format: "%.1f mi", mi) : "\(Int(mi.rounded())) mi"
        }
        if meters < 1000 { return "\(Int((meters / 50).rounded() * 50)) m" }
        let km = meters / 1000
        return km < 10 ? String(format: "%.1f km", km) : "\(Int(km.rounded())) km"
    }

    /// Distances as a voice says them: "half a mile", "2 miles", "800 meters".
    static func spoken(_ meters: Double) -> String {
        if useMiles {
            let mi = meters / 1609.344
            if mi < 0.3 { return "a quarter mile" }
            if mi < 0.6 { return "half a mile" }
            if mi < 1.3 { return "one mile" }
            return "\(Int(mi.rounded())) miles"
        }
        if meters < 950 { return "\(Int((meters / 100).rounded() * 100)) meters" }
        let km = meters / 1000
        return km < 1.5 ? "one kilometer" : "\(Int(km.rounded())) kilometers"
    }

    static func duration(_ seconds: Double) -> String {
        let m = Int((seconds / 60).rounded())
        if m < 60 { return "\(m) min" }
        return "\(m / 60) h \(m % 60) min"
    }

    /// A roadside weather reading. The feeds publish Celsius; Fahrenheit
    /// when chosen, or when the phone's region uses it.
    static func temperature(celsius: Double) -> String {
        fahrenheit ? "\(Int((celsius * 9 / 5 + 32).rounded()))\u{00B0}F" : "\(Int(celsius.rounded()))\u{00B0}C"
    }

    // MARK: overrides (absent follows the phone)

    static let clockKey = "cs.clock"          // absent, "12" or "24"
    static let temperatureKey = "cs.temp"     // absent, "f" or "c"

    /// Whether the phone's own region writes times on a 24-hour clock.
    static var phone24h: Bool {
        (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("H")
    }

    static var phoneMiles: Bool { Locale.current.measurementSystem == .us }

    static var clock24: Bool {
        switch UserDefaults.standard.string(forKey: clockKey) {
        case "24": return true
        case "12": return false
        default: return phone24h
        }
    }

    static var fahrenheit: Bool {
        switch UserDefaults.standard.string(forKey: temperatureKey) {
        case "f": return true
        case "c": return false
        default: return phoneMiles
        }
    }

    /// "8:42 AM", or "08:42" on a 24-hour clock.
    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.amSymbol = "AM"; f.pmSymbol = "PM"
        f.dateFormat = clock24 ? "HH:mm" : "h:mm a"
        return f.string(from: date)
    }

    /// Wind speed. The feeds publish miles per hour.
    static func speed(mph: Double) -> String {
        useMiles ? "\(Int(mph.rounded())) mph" : "\(Int((mph * 1.609344).rounded())) km/h"
    }

    /// The compass point a wind blows from, from its bearing in degrees.
    static func windDirection(_ degrees: Double) -> String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                      "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let i = Int((degrees / 22.5).rounded()) % points.count
        return points[i < 0 ? i + points.count : i]
    }
}
