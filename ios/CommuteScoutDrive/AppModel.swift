import Combine
import CoreLocation
@preconcurrency import FerrostarCore
@preconcurrency import FerrostarCoreFFI
import FerrostarSwiftUI
import Foundation
import MapLibre
import MapLibreSwiftUI
import UIKit

/// What the app is doing. One state, one screen per state.
enum DriveState: Equatable {
    case browsing                       // map, search bar, favorites
    case found(Place)                   // a pin with Navigate and Save
    case routing                        // fetching routes
    case choosing([Route], Place)       // alternatives before starting
    case navigating(Place)

    static func == (a: DriveState, b: DriveState) -> Bool {
        switch (a, b) {
        case (.browsing, .browsing), (.routing, .routing): true
        case let (.found(x), .found(y)): x.id == y.id
        case let (.choosing(_, x), .choosing(_, y)): x.id == y.id
        case let (.navigating(x), .navigating(y)): x.id == y.id
        default: false
        }
    }

    var isNavigating: Bool { if case .navigating = self { return true }; return false }
}

/// The location source: the phone, or a simulator that drives the
/// chosen route (debug builds only, for testing without a car).
final class LocationSource: LocationProviding {
    private let device = CoreLocationProvider(activityType: .automotiveNavigation,
                                              allowBackgroundLocationUpdates: true)
    private let simulated = SimulatedLocationProvider(location: CLLocation(latitude: 37.3382, longitude: -121.8863))
    var simulate = false { didSet { swapDelegate() } }

    private var current: LocationProviding { simulate ? simulated : device }

    init() { simulated.warpFactor = 3 }

    var delegate: (any LocationManagingDelegate)? {
        get { current.delegate }
        set { device.delegate = newValue; simulated.delegate = newValue }
    }

    private func swapDelegate() {
        let d = device.delegate ?? simulated.delegate
        device.delegate = d
        simulated.delegate = d
    }

    var authorizationStatus: CLAuthorizationStatus { device.authorizationStatus }
    var lastLocation: UserLocation? { current.lastLocation }
    var lastHeading: Heading? { current.lastHeading }
    func startUpdating() { current.startUpdating() }
    func stopUpdating() { current.stopUpdating() }

    func simulate(route: Route) throws {
        simulated.lastLocation = UserLocation(clCoordinateLocation2D: route.geometry.first!.clLocationCoordinate2D)
        try simulated.setSimulatedRoute(route, resampleDistance: 5)
    }

    var enabled: Bool {
        simulate || device.authorizationStatus == .authorizedAlways
            || device.authorizationStatus == .authorizedWhenInUse
    }

    var denied: Bool {
        !simulate && (device.authorizationStatus == .denied || device.authorizationStatus == .restricted)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var state: DriveState = .browsing
    @Published var camera: MapViewCamera = .default()
    @Published var coreState: NavigationState?
    @Published var errorMessage: String?
    @Published var muted = false
    @Published var preview: Route?          // the alternative under consideration
    @Published var selectedMarker: RoadMarker?
    @Published var heading: CLLocationDirection = 0
    var viewCenter: CLLocationCoordinate2D?      // what the map shows, from the hook
    var viewZoom: Double = 14
    @Published var isDark = false           // the current appearance, for the map style
    @Published var simulating = false { didSet { location.simulate = simulating } }
    @Published private(set) var core: FerrostarCore

    let location = LocationSource()
    let places = PlaceStore()
    let alerts = AlertsEngine()
    let markers = MarkerStore()
    let prefs = Prefs()
    let account = Account()
    lazy var push = PushRegistrar(account: account)
    let reporter = Reporter()
    let sources = SourcesStore()
    var origin: Place?                      // a chosen start instead of the driver
    @Published var toast: String?
    private let delegate = NavDelegate()
    private var accountSink: AnyCancellable?
    /// Optional via points for the next route (a corridor to prefer), cleared when a trip starts.
    var via: [CLLocationCoordinate2D] = []
    private var cancellables = Set<AnyCancellable>()
    private var coreSink: AnyCancellable?
    private var builtFor = ""
    private var previewCache: (key: String, feature: MLNPolylineFeature)?

    init() {
        core = Self.makeCore(location: location, prefs: prefs)
        builtFor = prefs.routingKey
        wireCore()
        core.delegate = delegate
        alerts.spoken = prefs.spokenAlerts
        alerts.announceAheadMeters = prefs.alertAheadMeters
        alerts.rules = { [prefs] m in prefs.rule(for: Prefs.ruleKind(for: m)) }
        location.startUpdating()
        camera = .center(Self.defaultCenter, zoom: 8)
        // Every dot has to be on the map by the time the camera finishes
        // its zoom to the driver, which takes a second or two. So the
        // launch snapshot is asked for here, while the map is still
        // loading its style and the camera is still moving, instead of
        // waiting for the map's view callback to ask for a viewport.
        markers.boot(near: Self.bootCenter(), cameras: prefs.isShown("camera"))
        prefs.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.prefsChanged() }
        }.store(in: &cancellables)
        // Views watch the model; changes in the stores it owns must show.
        for child in [places.objectWillChange.eraseToAnyPublisher(), markers.objectWillChange.eraseToAnyPublisher(),
                      alerts.objectWillChange.eraseToAnyPublisher(), account.objectWillChange.eraseToAnyPublisher(),
                      reporter.objectWillChange.eraseToAnyPublisher(), sources.objectWillChange.eraseToAnyPublisher()] {
            child.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }
        Task { await followOnceAllowed() }
    }

    /// Where the map opens before the first fix arrives.
    static let defaultCenter = CLLocationCoordinate2D(latitude: 37.5, longitude: -121.9)

    /// The best guess at where the phone is at the moment the app
    /// starts. Core Location keeps the last fix and hands it over
    /// without waiting for a new one; reading it does not ask for
    /// permission, and it is nil when permission was never given.
    private static func bootCenter() -> CLLocationCoordinate2D {
        if let fix = CLLocationManager().location?.coordinate, CLLocationCoordinate2DIsValid(fix) {
            return fix
        }
        return defaultCenter
    }

    // MARK: core

    private static func makeCore(location: LocationSource, prefs: Prefs) -> FerrostarCore {
        let config = SwiftNavigationControllerConfig(
            waypointAdvance: .waypointWithinRange(100.0),
            stepAdvanceCondition: stepAdvanceDistanceEntryAndExit(
                distanceToEndOfStep: 30, distanceAfterEndOfStep: 5, minimumHorizontalAccuracy: 32),
            arrivalStepAdvanceCondition: stepAdvanceDistanceToEndOfStep(
                distance: 10, minimumHorizontalAccuracy: 32),
            routeDeviationTracking: .staticThreshold(minimumHorizontalAccuracy: 15, maxAcceptableDeviation: 50),
            snappedLocationCourseFiltering: .snapToRoute
        )
        // Routing goes through commutescout.com: the key stays on the
        // server and every route carries the closure exclusions.
        var options: [String: Any] = ["units": Units.useMiles ? "miles" : "kilometers"]
        let costing = prefs.costingOptions
        if !costing.isEmpty { options["costing_options"] = costing }
        let provider = try! WellKnownRouteProvider.valhalla(
            endpointUrl: Backend.navRouteURL.absoluteString, profile: "auto")
            .withJsonOptions(options: options)
        // A bad provider is a programming error, not a runtime condition.
        return try! FerrostarCore(
            wellKnownRouteProvider: provider,
            locationProvider: location,
            navigationControllerConfig: config,
            annotation: AnnotationPublisher<ValhallaExtendedOSRMAnnotation>.valhallaExtendedOSRM()
        )
    }

    private func wireCore() {
        sources.tokenProvider = { [weak self] in await self?.account.token() }
        places.tokenProvider = { [weak self] in await self?.account.token() }
        account.beforeSignOut = { [weak self] in await self?.push.forget() }
        accountSink = account.$user.receive(on: DispatchQueue.main).sink { [weak self] u in
            guard u != nil else { return }
            Task {
                await self?.sources.pullFromAccount()
                await self?.places.syncWithAccount()
                await self?.push.requestPermission()
                await self?.push.register()
            }
        }
        coreSink = core.$state.receive(on: DispatchQueue.main).sink { [weak self] s in
            self?.noteLocation(s)
            guard let self else { return }
            self.coreState = s
            if let loc = s?.preferredUserLocation?.clLocation.coordinate, self.state.isNavigating {
                self.alerts.update(position: loc)
            }
        }
    }

    /// Settings changed: apply what applies now, and rebuild the core
    /// when nothing is running so the next request carries new options.
    private func prefsChanged() {
        alerts.spoken = prefs.spokenAlerts
        alerts.announceAheadMeters = prefs.alertAheadMeters
        if prefs.routingKey != builtFor, !state.isNavigating, coreState?.isNavigating != true {
            core = Self.makeCore(location: location, prefs: prefs)
            core.delegate = delegate
            wireCore()
            builtFor = prefs.routingKey
        }
        objectWillChange.send()
    }

    /// Follow the driver as soon as location is allowed (the first launch
    /// asks for permission, so this waits for the answer).
    private func followOnceAllowed() async {
        for _ in 0 ..< 120 {
            if location.enabled {
                if case .browsing = state { follow() }
                return
            }
            if location.denied {
                errorMessage = "Location is off for CommuteScout Drive. Turn it on in Settings to navigate."
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    // MARK: camera

    var here: CLLocationCoordinate2D? { location.lastLocation?.clLocation.coordinate }

    /// Where the driver is pointed, when known.
    var courseDegrees: Double? {
        let c = coreState?.preferredUserLocation?.clLocation.course ?? location.lastLocation?.clLocation.course
        return (c ?? -1) >= 0 ? c : nil
    }

    /// Where a report goes: the pin while browsing one, else the driver.
    var reportCoordinate: CLLocationCoordinate2D? {
        if case let .found(p) = state { return p.coordinate }
        return here
    }

    /// The base map for the current choice and appearance.
    var styleURL: URL { Backend.styleURL(prefs.mapStyle.serverStyle(dark: isDark)) }

    /// Keep the map on the driver, like a maps app at rest: north up in
    /// 2D, tilted in 3D.
    func follow() {
        camera = .trackUserLocation(zoom: 14, pitch: prefs.is3D ? 45 : 0)
    }

    /// The camera used while navigating, in 2D or 3D.
    var navigationCamera: MapViewCamera { .automotiveNavigation(pitch: prefs.is3D ? 45 : 0) }

    func toggle3D() {
        prefs.is3D.toggle()
        switch state {
        case .navigating: camera = navigationCamera
        case .browsing: follow()
        default: break
        }
    }

    /// North up, keeping the place and zoom.
    func faceNorth() {
        guard let c = viewCenter ?? here else { return }
        camera = .center(c, zoom: viewZoom, pitch: prefs.is3D ? 45 : 0, direction: 0)
    }

    // MARK: browsing

    func show(_ place: Place) {
        preview = nil
        selectedMarker = nil
        state = .found(place)
        camera = .center(place.coordinate, zoom: max(viewZoom, 14), pitch: prefs.is3D ? 45 : 0, direction: 0)
    }

    func clearFound() {
        origin = nil
        if case .found = state { state = .browsing; follow() }
    }

    func showMarker(key: String) {
        guard let m = marker(for: key) else { return }
        selectedMarker = m
        if case .found = state { state = .browsing }
    }

    func clearMarker() { selectedMarker = nil }

    // Drive log: a fix every few seconds is normal; a gap says the phone
    // lost GPS or the app was paused. A summary line every minute.
    private var lastFixAt: Date?
    private var fixes = 0
    private var lastSummary = Date()
    private var lastDeviating = false
    private func noteLocation(_ s: NavigationState?) {
        guard let loc = s?.preferredUserLocation else { return }
        let now = Date()
        if let last = lastFixAt, now.timeIntervalSince(last) > 15 {
            DriveLog.note("location gap \(Int(now.timeIntervalSince(last))) s")
        }
        lastFixAt = now
        fixes += 1
        if case .navigating = state, now.timeIntervalSince(lastSummary) >= 60 {
            let speed = loc.speed.map { String(format: "%.0f km/h", $0.value * 3.6) } ?? "?"
            DriveLog.note("nav: \(fixes) fixes/min, speed \(speed), acc \(Int(loc.horizontalAccuracy)) m, "
                          + "alerts ahead \(alerts.ahead.count)")
            fixes = 0
            lastSummary = now
        }
        if let dev = s?.currentDeviation {
            let off: Bool
            if case .noDeviation = dev { off = false } else { off = true }
            if off != lastDeviating {
                DriveLog.note(off ? "off route: rerouting" : "back on route")
                lastDeviating = off
            }
        }
    }

    /// A long press on the map: a pin named by Apple's reverse geocoder.
    func dropPin(at coordinate: CLLocationCoordinate2D) {
        let pending = Place(name: coordinate.pretty, coordinate: coordinate, kind: .recent)
        show(pending)
        Task {
            let geocoder = CLGeocoder()
            if let mark = try? await geocoder.reverseGeocodeLocation(
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)).first {
                let parts = [mark.name, mark.locality, mark.administrativeArea].compactMap { $0 }
                if case let .found(p) = state, p.id == pending.id, !parts.isEmpty {
                    var named = pending
                    named.name = parts.joined(separator: ", ")
                    state = .found(named)
                }
            }
        }
    }

    // MARK: routes

    /// Every marker on the map: the site's plus the driver's own plugins.
    /// Own-session markers replace the mediated copies of the same plugin.
    var allMarkers: [RoadMarker] {
        let own = sources.ownSessionIds
        let mediated = own.isEmpty ? markers.markers
            : markers.markers.filter { m in !own.contains(where: { (m.id ?? "").hasPrefix($0 + ":") }) }
        return mediated + sources.directMarkers
    }

    func marker(for key: String) -> RoadMarker? {
        markers.marker(for: key) ?? sources.directMarkers.first { $0.key == key }
    }

    func routes(to place: Place) async {
        // After time in the background the last fix can be minutes old; a
        // route from there starts with an immediate reroute. Wait briefly
        // for a fresh one.
        state = .routing   // "Finding routes" shows at once, wait or not
        if origin == nil, let ts = location.lastLocation?.clLocation.timestamp, Date().timeIntervalSince(ts) > 20 {
            DriveLog.note("routes: last fix \(Int(Date().timeIntervalSince(ts))) s old, waiting for a fresh one")
            for _ in 0 ..< 6 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let t2 = location.lastLocation?.clLocation.timestamp, Date().timeIntervalSince(t2) <= 20 { break }
            }
        }
        guard let from = origin?.coordinate ?? here else {
            DriveLog.note("routes: no position yet (denied=\(location.denied))")
            errorMessage = location.denied
                ? "Location is off for CommuteScout Drive. Turn it on in Settings to navigate."
                : "Waiting for your location."
            return
        }
        state = .routing
        do {
            let found = try await core.getRoutes(
                initialLocation: UserLocation(clCoordinateLocation2D: from),
                waypoints: via.map { Waypoint(coordinate: GeographicCoordinate(cl: $0), kind: .via) }
                    + [Waypoint(coordinate: GeographicCoordinate(cl: place.coordinate), kind: .break)])
            guard !found.isEmpty else { throw DriveError.noRoute }
            preview = found.first
            state = .choosing(found, place)
            if let bbox = found.first?.bbox {
                camera = .boundingBox(MLNCoordinateBounds(
                    sw: bbox.sw.clLocationCoordinate2D, ne: bbox.ne.clLocationCoordinate2D),
                    edgePadding: .init(top: 140, left: 40, bottom: 340, right: 40))
            }
        } catch {
            DriveLog.note("routes failed to '\(place.name)': \(error)")
            errorMessage = (error as? DriveError)?.errorDescription
                ?? "Could not get a route. Check your connection and try again."
            state = .found(place)
        }
    }

    func start(_ route: Route, to place: Place) {
        do {
            if simulating { try location.simulate(route: route) }
            try core.startNavigation(route: route)
            DriveLog.note("route start to '\(place.name)': \(DriveLog.meters(route.distance)) \(Int(route.steps.reduce(0) { $0 + $1.duration } / 60)) min, "
                          + "\(route.geometry.count) pts, simulated=\(simulating), alertsAhead=\(Int(prefs.alertAheadMeters)) m")
            preview = nil
            selectedMarker = nil
            origin = nil
            places.noteRecent(name: place.name, coordinate: place.coordinate)
            alerts.start(route: route.geometry.map(\.clLocationCoordinate2D))
            via = []
            delegate.onReroute = { [weak self] r in
                guard let self else { return }
                self.alerts.start(route: r.geometry.map(\.clLocationCoordinate2D))
                DriveLog.note("rerouted: \(DriveLog.meters(r.distance)), \(r.geometry.count) pts")
            }
            camera = navigationCamera
            state = .navigating(place)
            UIApplication.shared.isIdleTimerDisabled = prefs.keepAwake
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        DriveLog.note("route stop")
        core.stopNavigation()
        // Ferrostar stops location updates with the trip; start them again so
        // the puck stays live and the next route starts from where the phone is.
        location.startUpdating()
        alerts.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        state = .browsing
        follow()
    }

    func toggleMute() {
        core.spokenInstructionObserver.toggleMute()
        muted = core.spokenInstructionObserver.isMuted
    }

    /// The preview route as one polyline feature, built once per route.
    func previewFeature() -> MLNPolylineFeature? {
        guard case .choosing = state, let route = preview else { return nil }
        let last = route.geometry.last
        let key = "\(route.geometry.count)|\(route.distance)|\(last?.lat ?? 0)|\(last?.lng ?? 0)"
        if let c = previewCache, c.key == key { return c.feature }
        let coords = route.geometry.map(\.clLocationCoordinate2D)
        let f = MLNPolylineFeature(coordinates: coords, count: UInt(coords.count))
        previewCache = (key, f)
        return f
    }
}

enum DriveError: LocalizedError {
    case noRoute
    var errorDescription: String? {
        switch self { case .noRoute: "No route found. Try a different destination." }
    }
}

/// Rerouting: when the driver leaves the route, ask for a new one and
/// take it. The server applies the same closure exclusions every time.
final class NavDelegate: FerrostarCoreDelegate {
    /// The app's hook for a taken reroute: the alerts engine must follow the new geometry.
    var onReroute: ((Route) -> Void)?

    func core(_: FerrostarCore, didStartWith _: Route) {}

    func core(_: FerrostarCore, correctiveActionForDeviation _: DeviationKind,
              remainingWaypoints waypoints: [Waypoint]) -> CorrectiveAction {
        .getNewRoutes(waypoints: waypoints)
    }

    func core(_ core: FerrostarCore, loadedAlternateRoutes routes: [Route]) {
        guard core.state?.isCalculatingNewRoute ?? false, let route = routes.first else { return }
        try? core.startNavigation(route: route)
        onReroute?(route)
    }
}

extension CLLocationCoordinate2D {
    var pretty: String { String(format: "%.5f, %.5f", latitude, longitude) }
}
