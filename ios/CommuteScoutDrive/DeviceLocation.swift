import CoreLocation
@preconcurrency import FerrostarCore
@preconcurrency import FerrostarCoreFFI
import MapLibre

/// The phone's GPS, asked for only as much as the moment needs.
///
/// Ferrostar's own `CoreLocationProvider` asks for navigation-grade fixes
/// with no distance filter and the compass, all the time, from the
/// moment the app opens. Nothing in the app or in Ferrostar reads the
/// compass (FerrostarCore drops it), and navigation-grade fixes are only
/// worth their power on a trip. This provider does the same job and
/// takes its settings from `PowerPolicy.location`, which the model sets
/// as the trip and driving state change.
final class DeviceLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    var delegate: (any LocationManagingDelegate)?
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var lastLocation: UserLocation?
    /// Never set: the compass is not used.
    var lastHeading: Heading? { nil }

    private let manager = CLLocationManager()
    private(set) var setting = PowerPolicy.location(navigating: false, driving: false)

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        apply(setting)
        // As Ferrostar's provider: ask when never asked, else take the
        // last known fix and one fresh one.
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            lastLocation = manager.location?.userLocation
            manager.requestLocation()
        default:
            break
        }
    }

    /// Change what the GPS is asked for. Cheap when nothing changes.
    func apply(_ s: PowerPolicy.LocationSetting) {
        if manager.desiredAccuracy != s.accuracy { manager.desiredAccuracy = s.accuracy }
        if manager.distanceFilter != s.distanceFilter { manager.distanceFilter = s.distanceFilter }
        if manager.allowsBackgroundLocationUpdates != s.background { manager.allowsBackgroundLocationUpdates = s.background }
        if s != setting { DriveLog.note("gps: \(Self.describe(s))") }
        setting = s
    }

    static func describe(_ s: PowerPolicy.LocationSetting) -> String {
        let acc = s.accuracy == kCLLocationAccuracyBestForNavigation ? "navigation"
            : s.accuracy == kCLLocationAccuracyBest ? "best" : "\(Int(s.accuracy)) m"
        return "\(acc), every \(Int(s.distanceFilter)) m" + (s.background ? ", in background" : "")
    }

    func startUpdating() { manager.startUpdatingLocation() }
    func stopUpdating() { manager.stopUpdatingLocation() }

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last?.userLocation
        delegate?.locationManager(self, didUpdateLocations: locations.map(\.userLocation))
    }

    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        delegate?.locationManager(self, didFailWithError: error)
    }

    func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default: break
        }
    }
}

/// The map's location source when no trip is running.
///
/// Without one, MapLibre makes a location manager of its own and runs
/// it beside the app's at full accuracy: two GPS clients for one dot.
/// This hands the map the app's own fixes instead. A trip uses
/// Ferrostar's snapped puck, as before.
final class MapLocationFeed: NSObject, MLNLocationManager {
    weak var delegate: (any MLNLocationManagerDelegate)?
    var authorization: () -> CLAuthorizationStatus = { .notDetermined }
    var authorizationStatus: CLAuthorizationStatus { authorization() }
    var headingOrientation: CLDeviceOrientation = .portrait
    private(set) var last: CLLocation?
    private var running = false

    /// A new fix for the dot. Nothing is sent before the first real one,
    /// so the camera never follows a dot at 0,0.
    func push(_ location: CLLocation) {
        last = location
        if running { delegate?.locationManager(self, didUpdate: [location]) }
    }

    func requestAlwaysAuthorization() {}
    func requestWhenInUseAuthorization() {}

    func startUpdatingLocation() {
        running = true
        // Async, as MapLibre's SwiftUI wrapper does: a camera that follows
        // the user needs the map to have finished its own setup first.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, let l = self.last else { return }
            self.delegate?.locationManager(self, didUpdate: [l])
        }
    }

    func stopUpdatingLocation() { running = false }
    func startUpdatingHeading() {}
    func stopUpdatingHeading() {}
    func dismissHeadingCalibrationDisplay() {}
}
