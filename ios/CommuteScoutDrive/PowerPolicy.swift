import CoreLocation
import Foundation

/// How hard the app works in each situation, in one place (docs/battery.md).
///
/// A 20 minute drive used 10% of a healthy battery in 0.6.0. The causes
/// were the GPS asked for navigation-grade fixes and the compass every
/// moment the app was open, a second location manager inside the map,
/// the map drawn at the full display rate the whole drive, an alert ring
/// that kept the map drawing even at a red light, fetches that each woke
/// the cellular radio on their own timer, and the whole country's
/// markers rebuilt and re-sent to the map every minute. Everything here
/// is plain arithmetic so the tests can hold it.
enum PowerPolicy {
    // MARK: location

    struct LocationSetting: Equatable {
        let accuracy: CLLocationAccuracy
        let distanceFilter: CLLocationDistance
        /// Fixes keep coming with the screen off. Only a trip needs that:
        /// its turn prompts and alerts are spoken from the pocket.
        let background: Bool
    }

    /// What the GPS is asked for.
    ///
    /// A trip gets navigation-grade fixes, as before: turn prompts and
    /// rerouting depend on them. The 5 m filter only drops the fixes a
    /// parked phone produces from GPS noise; at any road speed a fix still
    /// comes every second. Driving with no destination needs a good
    /// course for the alert cone, not lane-level fixes. A phone that is
    /// not moving needs the dot on the map and enough to notice a drive
    /// starting.
    static func location(navigating: Bool, driving: Bool) -> LocationSetting {
        if navigating {
            return LocationSetting(accuracy: kCLLocationAccuracyBestForNavigation, distanceFilter: 5, background: true)
        }
        if driving {
            return LocationSetting(accuracy: kCLLocationAccuracyBest, distanceFilter: 10, background: false)
        }
        return LocationSetting(accuracy: kCLLocationAccuracyNearestTenMeters, distanceFilter: 15, background: false)
    }

    /// With a distance filter a phone stopped at a light gets no fixes,
    /// so a silent GPS is not a lost one. Only a car that was moving and
    /// then went quiet (a tunnel, a garage) has an unknown speed.
    static func speedUnknownAfterSilence(lastSpeed: Double) -> Bool { lastSpeed >= 2 }

    // MARK: map

    /// The map is drawn at 30 frames a second unless a finger is on it.
    /// Following a car at one fix a second, 30 looks the same as 60 and
    /// costs half the GPU time. 0 asks MapLibre for the display's most.
    static let cruisingFramesPerSecond = 30
    static func mapFramesPerSecond(touching: Bool) -> Int { touching ? 0 : cruisingFramesPerSecond }
    /// How long the full rate lasts after the finger lifts, for the fling.
    static let touchLinger: TimeInterval = 1.5

    /// The alert ring breathes for this long when a new alert takes the
    /// banner, then holds still: a breathing ring makes the map draw
    /// every frame, which is a red light's worth of battery for nothing.
    static let ringPulseSeconds: TimeInterval = 8

    /// The compass button turns with the map. Moves under this many
    /// degrees are not worth redrawing the screen for.
    static func headingWorthShowing(old: Double, new: Double) -> Bool {
        let d = abs(old - new).truncatingRemainder(dividingBy: 360)
        let turn = d > 180 ? 360 - d : d
        // Crossing the "is it turned at all" line always counts.
        return turn >= 2 || (abs(old) > 1) != (abs(new) > 1)
    }

    // MARK: network

    /// Every timed fetch runs on one beat, aligned to the clock, so they
    /// leave together. The cellular radio stays powered for several
    /// seconds after each request; four fetches a minute on four timers
    /// keep it up most of the minute, four on one beat keep it up once.
    static let beat: TimeInterval = 60

    /// The next time on the beat after `now`, at least `every` apart.
    static func nextBeat(after now: Date, every: TimeInterval = beat) -> Date {
        let step = max(beat, (every / beat).rounded(.up) * beat)
        let t = now.timeIntervalSince1970
        return Date(timeIntervalSince1970: (t / step).rounded(.down) * step + step)
    }

    /// A plugin's own cadence, put on the beat. Its alerts only draw on
    /// the map (spoken alerts come from the server), and it is asked
    /// for 50 km around the phone, so a minute keeps it well ahead.
    static func pluginEvery(requested: Int) -> TimeInterval {
        max(beat, (Double(requested) / beat).rounded(.up) * beat)
    }

    /// The country-wide snapshot is half a megabyte to fetch and nearly
    /// five to read. On the move the viewport and the route fetches carry
    /// everything near the car, so the rest of the country can wait.
    static func snapshotEvery(moving: Bool) -> TimeInterval { moving ? 30 * 60 : 10 * 60 }

    /// The viewport is fetched for a box snapped outward to a grid of
    /// cells this many degrees wide (about 5.5 km north to south), with a
    /// cell to spare on every side, so following the car down a road
    /// asks again every few kilometres instead of every few hundred
    /// metres, and a pan inside the box asks for nothing.
    static let cell = 0.05

    static func gridBox(south: Double, west: Double, north: Double, east: Double)
        -> (s: Double, w: Double, n: Double, e: Double) {
        func down(_ v: Double) -> Double { ((v / cell).rounded(.down) - 1) * cell }
        func up(_ v: Double) -> Double { ((v / cell).rounded(.up) + 1) * cell }
        return (down(south), down(west), up(north), up(east))
    }

    // MARK: route alerts

    /// On a trip the alerts are fetched for the road ahead, not the whole
    /// route: from a kilometre behind to this far ahead.
    static let routeAhead = 50_000.0
    static let routeBehind = 1_000.0
    /// The window moves on when the car is this far into it.
    static let routeSlide = 25_000.0

    /// The route's vertices inside the window, as an index range.
    static func routeWindow(cumulative: [Double], here: Double) -> ClosedRange<Int>? {
        guard cumulative.count > 1 else { return nil }
        let from = cumulative.firstIndex { $0 >= here - routeBehind }.map { max(0, $0 - 1) } ?? cumulative.count - 2
        let to = cumulative.firstIndex { $0 > here + routeAhead } ?? cumulative.count - 1
        return from ... max(from + 1, to)
    }
}

extension Timer {
    /// A repeating timer on the shared beat (PowerPolicy.nextBeat), with
    /// a little slack so the system can wake once for all of them.
    static func onBeat(every: TimeInterval = PowerPolicy.beat, _ block: @escaping @MainActor () -> Void) -> Timer {
        let t = Timer(fire: PowerPolicy.nextBeat(after: Date(), every: every), interval: every, repeats: true) { _ in
            MainActor.assumeIsolated { block() }
        }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        return t
    }
}
