import Foundation
import CoreLocation

/// Whether the sun is up at a place, for the "Dark after sunset"
/// theme. A short almanac formula, good to about a minute at ordinary
/// latitudes, with no network and no table.
enum Daylight {
    /// The sun counts as up above this, in degrees: its disc and the air's bending put sunrise at -0.833.
    static let horizon = -0.833

    /// The sun's height over the horizon in degrees.
    static func sunElevation(lat: Double, lon: Double, at date: Date) -> Double {
        let rad = Double.pi / 180
        let n = date.timeIntervalSince1970 / 86_400 - 10957.5      // days since noon, 1 Jan 2000 UTC
        let meanLon = mod(280.460 + 0.9856474 * n, 360) * rad
        let anomaly = mod(357.528 + 0.9856003 * n, 360) * rad
        let ecliptic = meanLon + (1.915 * sin(anomaly) + 0.020 * sin(2 * anomaly)) * rad
        let tilt = (23.439 - 0.0000004 * n) * rad
        let rightAscension = atan2(cos(tilt) * sin(ecliptic), cos(ecliptic))
        let declination = asin(sin(tilt) * sin(ecliptic))
        let siderealHours = mod(18.697374558 + 24.06570982441908 * n, 24)
        let hourAngle = (siderealHours * 15 + lon) * rad - rightAscension
        let la = lat * rad
        return asin(sin(la) * sin(declination) + cos(la) * cos(declination) * cos(hourAngle)) / rad
    }

    /// True in daylight. With a position it follows the sun there;
    /// without one it falls back to the clock: day from 7 in the
    /// morning to 7 in the evening.
    static func isDay(here: CLLocationCoordinate2D?, at date: Date, calendar: Calendar = .current) -> Bool {
        if let here { return sunElevation(lat: here.latitude, lon: here.longitude, at: date) > horizon }
        return (7...18).contains(calendar.component(.hour, from: date))
    }

    private static func mod(_ a: Double, _ b: Double) -> Double { (a.truncatingRemainder(dividingBy: b) + b).truncatingRemainder(dividingBy: b) }
}
