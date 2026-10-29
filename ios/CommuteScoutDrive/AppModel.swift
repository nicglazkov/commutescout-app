import AVFoundation
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

/// Sits between the location provider and the routing core. The core
/// ignores a fix unless a trip is running; the app wants every one, for
/// driving mode and for alerts on a drive with no destination.
final class LocationRelay: LocationManagingDelegate {
    weak var core: FerrostarCore?
    var onFix: ((UserLocation) -> Void)?

    func locationManager(_ manager: LocationProviding, didUpdateLocations locations: [UserLocation]) {
        core?.locationManager(manager, didUpdateLocations: locations)
        if let last = locations.last { onFix?(last) }
    }

    func locationManager(_ manager: LocationProviding, didUpdateHeading newHeading: Heading) {
        core?.locationManager(manager, didUpdateHeading: newHeading)
    }

    func locationManager(_ manager: LocationProviding, didFailWithError error: Error) {
        core?.locationManager(manager, didFailWithError: error)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var state: DriveState = .browsing
    /// Driving mode: the phone is moving at road speed with no trip
    /// running. The map turns to face the way the car is pointed and
    /// the dot becomes an arrow, as it does on a trip.
    @Published private(set) var driving = false
    /// The last fix's speed in m/s (negative when unknown), for the speedometer.
    @Published private(set) var speedMps: Double = -1
    /// The posted limit on the road ahead while driving with no trip,
    /// km/h, asked of the server once a minute at most. A trip carries
    /// its own limit in the route's annotations.
    @Published private(set) var postedLimitKmh: Double?
    private var limitAskedAt = Date.distantPast
    private var limitAskedAtPoint: CLLocationCoordinate2D?
    private var lastFixForSpeed: (CLLocationCoordinate2D, Date)?
    @Published var camera: MapViewCamera = .default()
    @Published var coreState: NavigationState?
    @Published var errorMessage: String?
    @Published var muted = false
    @Published var preview: Route?          // the alternative under consideration
    @Published var selectedMarker: RoadMarker?
    /// A watch alert being shown in the event sheet, and what became of
    /// its event. Nil for a marker the person tapped on the map.
    @Published var alertFocus: AlertFocus?
    /// The shown marker dropped out of the live data while its sheet was
    /// open: the sheet says so instead of closing.
    @Published var selectedVanished = false
    /// An alert tapped during a trip, opened when the trip ends.
    private var parkedAlert: AlertRef?
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
    let mapFiles = MapFiles.shared
    var origin: Place?                      // a chosen start instead of the driver
    @Published var toast: String?
    /// A trip that was running when the app last closed, offered back.
    @Published var resumable: SavedTrip?
    private var flushing = false
    private let delegate = NavDelegate()
    private var accountSink: AnyCancellable?
    /// Optional via points for the next route (a corridor to prefer), cleared when a trip starts.
    var via: [CLLocationCoordinate2D] = []
    private var cancellables = Set<AnyCancellable>()
    private var coreSink: AnyCancellable?
    private var builtFor = ""
    private var previewCache: (key: String, feature: MLNPolylineFeature)?
    private let relay = LocationRelay()
    private var movingSince: Date?
    private var stillSince: Date?
    private var sceneCache: (key: String, scene: MapOverlay.Scene)?

    init() {
        core = Self.makeCore(location: location, prefs: prefs)
        builtFor = prefs.routingKey
        wireCore()
        core.delegate = delegate
        alerts.spoken = prefs.spokenAlerts
        alerts.announceAheadMeters = prefs.alertAheadMeters
        alerts.rules = { [prefs] m in prefs.rule(for: Prefs.ruleKind(for: m)) }
        alerts.fallback = { [weak self] in (self?.allMarkers ?? [], self?.markers.asOf) }
        location.startUpdating()
        // The live map asks the server for community plugin alerts
        // around where this phone actually is, and gets none at all
        // without saying. Reading it through a closure keeps Backend
        // free of the model and follows a simulated drive too.
        LiveData.position = { [weak self] in self?.here }
        LiveData.routeAhead = { [weak self] in self?.alerts.stretchAhead() ?? [] }
        relay.onFix = { [weak self] loc in Task { @MainActor in self?.noteFix(loc) } }
        alerts.startFreeDrive()
        mapFiles.position = { [weak self] in self?.here ?? self?.viewCenter }
        camera = .center(Self.defaultCenter, zoom: 8)
        // Every dot has to be on the map by the time the camera finishes
        // its zoom to the driver, which takes a second or two. So the
        // launch snapshot is asked for here, while the map is still
        // loading its style and the camera is still moving, instead of
        // waiting for the map's view callback to ask for a viewport.
        markers.boot(cameras: prefs.isShown("camera"))
        prefs.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.prefsChanged() }
        }.store(in: &cancellables)
        // Views watch the model; changes in the stores it owns must show.
        for child in [places.objectWillChange.eraseToAnyPublisher(), markers.objectWillChange.eraseToAnyPublisher(),
                      alerts.objectWillChange.eraseToAnyPublisher(), account.objectWillChange.eraseToAnyPublisher(),
                      reporter.objectWillChange.eraseToAnyPublisher(), sources.objectWillChange.eraseToAnyPublisher(),
                      Connectivity.shared.objectWillChange.eraseToAnyPublisher(), mapFiles.objectWillChange.eraseToAnyPublisher()] {
            child.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }
        Connectivity.shared.onReconnect { [weak self] in self?.reconnected() }
        markers.$stamp.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.checkSelectedStillThere() }
            .store(in: &cancellables)
        AlertInbox.shared.handler = { [weak self] ref in self?.openAlert(ref) }
        resumable = SavedTrip.load()
        if let trip = resumable { DriveLog.note("a trip was running when the app closed; offering it back") }
        Task { await followOnceAllowed() }
        Task { await flushReports() }
    }

    /// The signal is back: spoken alerts catch up and any report made
    /// meanwhile goes out. The marker store catches itself up.
    private func reconnected() {
        alerts.refreshNow()
        Task { await flushReports() }
    }

    // MARK: offline

    var online: Bool { Connectivity.shared.online }

    /// Off the route line, as Ferrostar sees it.
    var isOffRoute: Bool {
        guard let dev = coreState?.currentDeviation else { return false }
        if case .noDeviation = dev { return false }
        return true
    }

    /// What the offline banner says, or nil while online.
    var offlineNotice: (title: String, detail: String)? {
        guard !online else { return nil }
        let asOf = markers.asOf.map { "as of " + OfflineText.time($0) }
        if state.isNavigating {
            if isOffRoute {
                return ("No signal to reroute", "Head back to the route. Rerouting resumes when you are back online.")
            }
            return ("No connection", "Guidance continues." + (asOf.map { " Alerts \($0)." } ?? ""))
        }
        if markers.asOf == nil { return ("No connection", "The map fills in when you are back online.") }
        return ("No connection", "Showing road reports " + (asOf ?? "saved earlier") + ".")
    }

    /// Reports made without a signal, sent now. One that waited past
    /// `PendingReport.maxAge` is dropped instead, because the server
    /// would stamp it as new.
    func flushReports() async {
        // Launch and a reconnect can both ask at once; one sender only,
        // or a queued report goes out twice.
        guard !flushing else { return }
        flushing = true
        defer { flushing = false }
        let pending = PendingReport.all()
        guard !pending.isEmpty, online else { return }
        guard let token = await account.token() else { return }
        var sent: [PendingReport] = [], waiting: [PendingReport] = [], dropped = 0, refused = 0
        for r in pending {
            if Date().timeIntervalSince(r.createdAt) > PendingReport.maxAge {
                dropped += 1
                DriveLog.note("report \(r.kind) from \(OfflineText.time(r.createdAt)) dropped: too old to send")
                continue
            }
            do {
                try await reporter.send(kind: r.kind, at: CLLocationCoordinate2D(latitude: r.lat, longitude: r.lon),
                                        heading: r.heading, description: r.note, token: token)
                sent.append(r)
            } catch {
                if Connectivity.isOffline(error) { waiting.append(r) } else { refused += 1; DriveLog.note("queued report refused: \(error)") }
            }
        }
        PendingReport.store(waiting)
        if let first = sent.first {
            toast = sent.count == 1 ? "Your report from \(OfflineText.time(first.createdAt)) was sent."
                : "\(sent.count) reports you made offline were sent."
            markers.refresh(force: true)
        } else if dropped > 0 {
            toast = dropped == 1 ? "A report made offline was too old to send."
                : "\(dropped) reports made offline were too old to send."
        } else if refused > 0 {
            toast = "A report made offline could not be sent."
        }
    }

    /// Take the saved trip back up.
    func resume() {
        guard let trip = resumable else { return }
        guard here != nil || simulating else {
            errorMessage = "Waiting for your location. Try again in a moment."
            return
        }
        resumable = nil
        DriveLog.note("resume trip, saved \(Int(Date().timeIntervalSince(trip.startedAt))) s ago")
        start(trip.route, to: trip.place)
    }

    func dismissResume() {
        resumable = nil
        SavedTrip.clear()
    }

    /// Where the map opens before the first fix arrives.
    static let defaultCenter = CLLocationCoordinate2D(latitude: 37.5, longitude: -121.9)

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
        // The app's own session: a 20 second timeout rather than the
        // shared session's 60, so "Finding routes" on a weak signal gives
        // up in reasonable time, and the app's User-Agent.
        return try! FerrostarCore(
            wellKnownRouteProvider: provider,
            locationProvider: location,
            navigationControllerConfig: config,
            networkSession: Backend.session,
            annotation: AnnotationPublisher<ValhallaExtendedOSRMAnnotation>.valhallaExtendedOSRM(),
            // The same observer initAVSpeechSynthesizer makes (mute, queue,
            // audio focus), with each sentence said in the app's voice.
            spokenInstructionObserver: SpokenInstructionObserver(
                synthesizer: VoicedSynthesizer(Voice.synth), isMuted: false)
        )
    }

    private func wireCore() {
        relay.core = core
        location.delegate = relay
        sources.tokenProvider = { [weak self] in await self?.account.token() }
        places.tokenProvider = { [weak self] in await self?.account.token() }
        account.beforeSignOut = { [weak self] in
            await self?.push.forget()
            await self?.places.forgetForSignOut()
            self?.sources.forgetForSignOut()
        }
        account.afterDelete = { [weak self] in
            await self?.places.forgetForSignOut(flush: false)
            self?.sources.forgetForSignOut()
        }
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
                NeuralVoices.shared.setAlong(self.alerts.hereAlong)
            }
            // Arrived: nothing left to resume.
            if case .complete = s?.tripState { SavedTrip.clear() }
        }
    }

    /// Settings changed: apply what applies now, and rebuild the core
    /// when nothing is running so the next request carries new options.
    private func prefsChanged() {
        alerts.spoken = prefs.spokenAlerts && !muted
        applyIdleTimer()
        alerts.announceAheadMeters = prefs.alertAheadMeters
        // Cameras are published as an object of their own and are only
        // worth fetching while the snapshot is still what the map shows.
        if prefs.isShown("camera") { markers.load(.cameras) }
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

    /// The base map for the current choice and appearance: a bundled
    /// style, drawing from the online file or a saved one (MapFiles).
    var styleURL: URL { mapFiles.styleURL(flavor: prefs.mapStyle.flavor(dark: isDark)) }

    /// The map along this route, saved for the drive. Automatic on
    /// Wi-Fi when the setting allows; `manual` is the driver's tap.
    func saveTripMap(_ route: Route, to place: Place, manual: Bool) {
        Task {
            await mapFiles.saveCorridor(route: route.geometry.map(\.clLocationCoordinate2D), name: place.shortName,
                                        manual: manual, autoAllowed: prefs.mapAutoSave)
            if let n = mapFiles.lastNotice { toast = n; mapFiles.lastNotice = nil }
        }
    }

    /// Keep the map on the driver, like a maps app at rest: north up in
    /// 2D, tilted in 3D. Moving, the map faces the way the car points
    /// and the dot is an arrow, with or without a destination.
    func follow() {
        if driving {
            camera = .trackUserLocationWithCourse(zoom: 15, pitch: prefs.is3D ? 45 : 0)
        } else {
            camera = .trackUserLocation(zoom: 14, pitch: prefs.is3D ? 45 : 0)
        }
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
        clearMarker()
        origin = nil
        state = .found(place)
        camera = .center(place.coordinate, zoom: max(viewZoom, 14), pitch: prefs.is3D ? 45 : 0, direction: 0)
    }

    func clearFound() {
        origin = nil
        if case .found = state { state = .browsing; follow() }
    }

    func showMarker(key: String) {
        guard let m = marker(for: key) else { return }
        // On a trip the bottom belongs to the trip bar; a card there
        // would cover it and the speedometer. The tap speaks the thing.
        if state.isNavigating { alerts.say(m); return }
        select(m)
    }

    /// Show one marker in the event sheet, as a plain map tap does.
    func select(_ m: RoadMarker) {
        alertFocus = nil
        selectedVanished = false
        selectedMarker = m
        if case .found = state { state = .browsing }
    }

    func clearMarker() {
        selectedMarker = nil
        alertFocus = nil
        selectedVanished = false
    }

    // MARK: tapped alerts

    /// A watch alert was tapped: go to the event and open its sheet at
    /// once with what the alert said, then ask what became of it. The
    /// sheet is never empty and never shows a different event as if it
    /// were the one in the alert.
    func openAlert(_ ref: AlertRef) {
        DriveLog.note("alert opened: \(ref.kind)")
        // On a trip the screen belongs to the trip: the alert waits
        // for the trip to end.
        if state.isNavigating {
            parkedAlert = ref
            toast = "Watch alert saved. It opens when this trip ends."
            return
        }
        preview = nil
        if case .found = state { state = .browsing }
        focusEvent(ref.coordinate)
        selectedVanished = false
        selectedMarker = ref.localMatch(in: allMarkers)
        alertFocus = AlertFocus(ref: ref)
        Task { await checkAlert(ref) }
    }

    /// Put an event in the upper part of the map, above the event panel
    /// that covers the lower half, rather than at the screen's center.
    func focusEvent(_ c: CLLocationCoordinate2D, zoom: Double = 14) {
        // MapLibre's world is 512 points wide at zoom 0.
        let metersPerPoint = 40_075_016 * cos(c.latitude * .pi / 180) / (512 * pow(2, zoom))
        let shift = 0.22 * UIScreen.main.bounds.height * metersPerPoint / 111_320
        camera = .center(CLLocationCoordinate2D(latitude: c.latitude - shift, longitude: c.longitude),
                         zoom: zoom, pitch: 0, direction: 0)
    }

    /// Ask again, after a failed check.
    func recheckAlert() {
        guard let ref = alertFocus?.ref else { return }
        alertFocus?.status = .loading
        Task { await checkAlert(ref) }
    }

    private func checkAlert(_ ref: AlertRef) async {
        let reply = try? await EventAPI.status(ref)
        // The person may have moved on while the answer was on its way.
        guard alertFocus?.ref == ref else { return }
        let (status, marker, nearby) = AlertFocus.resolve(reply, local: ref.localMatch(in: allMarkers))
        alertFocus?.status = status
        alertFocus?.checkedAt = Date()
        alertFocus?.nearby = nearby
        selectedMarker = marker
        if let marker, marker.lat != ref.lat || marker.lon != ref.lon {
            focusEvent(marker.coordinate)
        }
        DriveLog.note("alert status: \(reply?.state ?? "unreachable")")
    }

    /// After a refresh: a shown marker that is no longer reported is
    /// said to be gone, rather than the sheet closing under the person.
    private func checkSelectedStillThere() {
        guard let m = selectedMarker, !selectedVanished, m.isEvent, markers.asOf != nil else { return }
        guard marker(for: m.key) == nil else { return }
        // Direct plugin markers and anything fetched for the sheet alone
        // are not in the store: only a key that was there and left counts.
        guard markers.knew(m.key) else { return }
        selectedVanished = true
        if alertFocus != nil {
            alertFocus?.status = .gone
            alertFocus?.checkedAt = Date()
        }
    }

    /// The phone went to the background with no trip running: let go of
    /// GPS and stop the polling, so a pocketed phone does not hold a
    /// fix and hit the network all day. A trip keeps everything, which
    /// is what the location background mode is for.
    func pauseIfIdle() {
        guard !state.isNavigating else { return }
        NeuralVoices.shared.free("in the background")
        location.stopUpdating()
        alerts.stop()
        markers.pause()
        DriveLog.note("background: location and polling paused")
    }

    /// Back in front: everything that was paused.
    func resumeFromBackground() {
        location.startUpdating()
        if !state.isNavigating { alerts.startFreeDrive() }
        markers.resume()
        speedMps = -1
    }

    // Drive log: a fix every few seconds is normal; a gap says the phone
    // lost GPS or the app was paused. A summary line every minute.
    private var lastFixAt: Date?
    private var staleSpeedTimer: Timer?
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
        staleSpeedTimer?.invalidate()
        // No fix for a while (a tunnel, a garage): the speedometer must
        // not keep showing the last speed as if it were now.
        staleSpeedTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.speedMps = -1 }
        }
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

    /// Whether a marker's plugin is switched on. Official markers always are.
    func pluginIsOn(_ m: RoadMarker) -> Bool {
        m.kind != "plugin" || sources.isOn(PluginStyle.sourceId(m))
    }

    struct PluginBadgeKey: Hashable { let key: String; let sourceId: String; let category: String }

    /// Every badge on the map right now: one per plugin and category.
    var pluginBadges: [PluginBadgeKey] {
        guard prefs.isShown("plugin") else { return [] }
        var seen = Set<PluginBadgeKey>()
        for m in allMarkers where m.kind == "plugin" && pluginIsOn(m) {
            seen.insert(PluginBadgeKey(key: PluginStyle.key(m), sourceId: PluginStyle.sourceId(m),
                                       category: PluginStyle.category(m.flareKind)))
        }
        return seen.sorted { $0.key < $1.key }
    }

    func marker(for key: String) -> RoadMarker? {
        markers.marker(for: key) ?? sources.directMarkers.first { $0.key == key }
    }

    /// The shapes the map draws besides the dots: closure stretches,
    /// toll corridors and burn footprints, each following the ground
    /// rather than a straight line between two points.
    struct MapShapes {
        var closures: [MLNShape] = []
        var tolls: [MLNShape] = []
        var fires: [MLNShape] = []
    }

    private var shapeCache: (key: String, shapes: MapShapes)?

    /// Built once per marker refresh, not once per frame. The map
    /// content is rebuilt on every model change, and a single burn
    /// footprint can run to a thousand points across seven rings.
    func mapShapes() -> MapShapes {
        let key = "\(markers.stamp)|\(prefs.layersOff)|\(prefs.sourceFilterRaw)|\(sources.directMarkers.count)"
        if let cached = shapeCache, cached.key == key { return cached.shapes }
        var out = MapShapes()
        for m in allMarkers where prefs.isShown(m.kind) {
            switch m.kind {
            case "lane_closure":
                out.closures.append(contentsOf: m.polylines.map { Self.line($0, for: m) })
            case "toll":
                out.tolls.append(contentsOf: m.polylines.map { Self.line($0, for: m) })
            case "wildfire":
                out.fires.append(contentsOf: m.polygonRings.map { Self.ring($0, for: m) })
            default:
                break
            }
        }
        shapeCache = (key, out)
        return out
    }

    private static func line(_ points: [CLLocationCoordinate2D], for m: RoadMarker) -> MLNShape {
        let feature = MLNPolylineFeature(coordinates: points, count: UInt(points.count))
        feature.attributes = ["key": m.key, "kind": m.kind, "geo": "line"]
        return feature
    }

    private static func ring(_ points: [CLLocationCoordinate2D], for m: RoadMarker) -> MLNShape {
        let feature = MLNPolygonFeature(coordinates: points, count: UInt(points.count))
        feature.attributes = ["key": m.key, "kind": m.kind, "geo": "area"]
        return feature
    }

    func routes(to place: Place) async {
        // After time in the background the last fix can be minutes old; a
        // route from there starts with an immediate reroute. Wait briefly
        // for a fresh one.
        state = .routing   // "Finding routes" shows at once, wait or not
        // A newer request, or Cancel, bumps the generation: this one's
        // answer must not land on top of whatever the driver moved on to.
        routeGen += 1
        let gen = routeGen
        routingPlace = place
        if origin == nil, let ts = location.lastLocation?.clLocation.timestamp, Date().timeIntervalSince(ts) > 20 {
            DriveLog.note("routes: last fix \(Int(Date().timeIntervalSince(ts))) s old, waiting for a fresh one")
            for _ in 0 ..< 6 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let t2 = location.lastLocation?.clLocation.timestamp, Date().timeIntervalSince(t2) <= 20 { break }
            }
        }
        guard gen == routeGen else { return }
        guard let from = origin?.coordinate ?? here else {
            DriveLog.note("routes: no position yet (denied=\(location.denied))")
            // Back to the pin, or "Finding routes" stays up behind the
            // alert with no way to dismiss it.
            state = .found(place)
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
            guard gen == routeGen else { return }
            guard !found.isEmpty else { throw DriveError.noRoute }
            preview = found.first
            state = .choosing(found, place)
            // The first sentences of the likely route, while the driver
            // looks at the choices: they are said the moment it starts.
            if let first = found.first { prerenderSpeech(first, from: 0, limit: 3) }
            if let bbox = found.first?.bbox {
                camera = .boundingBox(MLNCoordinateBounds(
                    sw: bbox.sw.clLocationCoordinate2D, ne: bbox.ne.clLocationCoordinate2D),
                    edgePadding: .init(top: 140, left: 40, bottom: 340, right: 40))
            }
        } catch {
            guard gen == routeGen else { return }
            DriveLog.note("routes failed: \(error)")
            errorMessage = (error as? DriveError)?.errorDescription
                ?? (!online || Connectivity.isOffline(error) ? OfflineText.routes
                    : "Could not get a route. Try again in a moment.")
            state = .found(place)
        }
    }

    private var routeGen = 0
    private var routingPlace: Place?

    /// "Finding routes" can take twenty seconds on a weak signal: back to the pin.
    func cancelRouting() {
        routeGen += 1
        guard case .routing = state else { return }
        state = routingPlace.map { .found($0) } ?? .browsing
    }

    func start(_ route: Route, to place: Place) {
        do {
            if simulating { try location.simulate(route: route) }
            try core.startNavigation(route: route)
            SavedTrip.save(route: route, place: place)
            saveTripMap(route, to: place, manual: false)
            DriveLog.note("route start: \(DriveLog.meters(route.distance)) \(Int(route.steps.reduce(0) { $0 + $1.duration } / 60)) min, "
                          + "\(route.geometry.count) pts, simulated=\(simulating), alertsAhead=\(Int(prefs.alertAheadMeters)) m")
            preview = nil
            clearMarker()
            origin = nil
            places.noteRecent(name: place.name, coordinate: place.coordinate)
            prerenderSpeech(route, from: 0)
            alerts.start(route: route.geometry.map(\.clLocationCoordinate2D))
            via = []
            resumable = nil
            delegate.onReroute = { [weak self] r in
                guard let self else { return }
                self.prerenderSpeech(r, from: 0)
                self.alerts.start(route: r.geometry.map(\.clLocationCoordinate2D))
                SavedTrip.save(route: r, place: place)
                DriveLog.note("rerouted: \(DriveLog.meters(r.distance)), \(r.geometry.count) pts")
            }
            camera = navigationCamera
            state = .navigating(place)
            applyIdleTimer()
            speechWarmth()
        } catch {
            DriveLog.note("route start failed: \(error)")
            errorMessage = here == nil ? "Waiting for your location. Try again in a moment."
                : "Could not start navigation. Try again."
        }
    }

    func stop() {
        DriveLog.note("route stop")
        NeuralVoices.shared.clearQueue()
        SavedTrip.clear()
        core.stopNavigation()
        // Ferrostar stops location updates with the trip; start them again so
        // the puck stays live and the next route starts from where the phone is.
        location.startUpdating()
        alerts.startFreeDrive()
        state = .browsing
        applyIdleTimer()
        speechWarmth()
        follow()
        if let ref = parkedAlert { parkedAlert = nil; openAlert(ref) }
    }

    /// With a CommuteScout voice, every spoken instruction of the route
    /// is rendered now, in the order it will be said, so the voice never
    /// has to be made while the driver waits. The text is built the way
    /// Ferrostar builds it and `VoicedSynthesizer` reads it back, so the
    /// cached audio matches the sentence when it comes.
    func prerenderSpeech(_ route: Route, from along: Double, limit: Int = .max) {
        guard Voice.neural != nil else { return }
        NeuralVoices.shared.clearQueue()
        let due = NeuralPlan.instructionDue(stepDistances: route.steps.map(\.distance),
                                            triggers: route.steps.map { $0.spokenInstructions.map(\.triggerDistanceBeforeManeuver) })
        var items: [(text: String, due: Double)] = []
        for (i, step) in route.steps.enumerated() {
            for (j, instruction) in step.spokenInstructions.enumerated() {
                let u: AVSpeechUtterance = if let ssml = instruction.ssml, let s = AVSpeechUtterance(ssmlRepresentation: ssml) { s }
                    else { AVSpeechUtterance(string: instruction.text) }
                let text = Voice.plainText(u)
                if !text.isEmpty, !items.contains(where: { $0.text == text }) { items.append((text, due[i][j])) }
                if items.count >= limit { break }
            }
            if items.count >= limit { break }
        }
        DriveLog.note("neural: queued \(items.count) instructions to render")
        NeuralVoices.shared.prerender(items.filter { $0.due >= along - 50 })
    }

    /// The engine is kept loaded while a trip or a drive runs, and let
    /// go otherwise.
    private func speechWarmth() {
        let warm = state.isNavigating || driving
        NeuralVoices.shared.setKeepWarm(warm)
    }

    // MARK: driving mode

    /// Every fix, on a trip or not. Road speed for a few seconds turns
    /// driving mode on; a stop of a minute turns it off. A trip has its
    /// own camera and its own alerts, so neither changes during one.
    private func noteFix(_ loc: UserLocation) {
        let cl = loc.clLocation
        let now = Date()
        var speed = cl.speed            // m/s, negative when unknown
        // A fix without a speed (the simulator, some chipsets): the pace
        // between this fix and the last one stands in.
        if speed < 0, let (p, t) = lastFixForSpeed, cl.timestamp.timeIntervalSince(t) > 0.3 {
            speed = AlertsEngine.meters(p, cl.coordinate) / cl.timestamp.timeIntervalSince(t)
        }
        lastFixForSpeed = (cl.coordinate, cl.timestamp)
        let course = cl.course >= 0 ? cl.course : nil
        speedMps = speed
        if !state.isNavigating {
            alerts.update(position: cl.coordinate, course: course, speed: speed)
            askPostedLimit(at: cl.coordinate, course: course, speed: speed)
        }
        if speed >= 3 {                 // about 7 mph
            stillSince = nil
            if movingSince == nil { movingSince = now }
            if !driving, now.timeIntervalSince(movingSince ?? now) >= 3 { setDriving(true) }
        } else if speed >= 0, speed < 1 {
            movingSince = nil
            if stillSince == nil { stillSince = now }
            if driving, now.timeIntervalSince(stillSince ?? now) >= 60 { setDriving(false) }
        }
    }

    /// The limit on the road ahead, once a minute or every 500 m while
    /// moving, with no trip running (a trip's route carries its own).
    /// An unknown answer clears the sign rather than leaving a stale one.
    private func askPostedLimit(at p: CLLocationCoordinate2D, course: Double?, speed: Double) {
        guard speed >= 4, online, let course else { return }
        let now = Date()
        let moved = limitAskedAtPoint.map { AlertsEngine.meters($0, p) } ?? .infinity
        guard now.timeIntervalSince(limitAskedAt) >= 45 || moved >= 500 else { return }
        limitAskedAt = now
        limitAskedAtPoint = p
        Task { [weak self] in
            struct Limit: Decodable { let kmh: Double? }
            let q = ["lat": String(format: "%.5f", p.latitude), "lon": String(format: "%.5f", p.longitude),
                     "heading": String(format: "%.0f", course)]
            let got = try? await Backend.get("api/speedlimit", query: q, as: Limit.self)
            await MainActor.run { self?.postedLimitKmh = got?.kmh }
        }
    }

    /// Whether a marker's plugin takes confirmations (Still there / Gone).
    func canConfirm(_ m: RoadMarker) -> Bool {
        guard m.kind == "plugin", m.id != nil else { return false }
        let sid = PluginStyle.sourceId(m)
        return (sources.catalog.first { $0.id == sid } ?? sources.mine.first { $0.id == sid })?.canConfirm ?? false
    }

    /// A vote on a community report, from the banner: no sheets while
    /// driving, a toast says what happened or what is needed.
    func vote(_ m: RoadMarker, _ v: String) async {
        guard let id = m.id else { return }
        guard online else { toast = "No signal: the vote did not go through."; return }
        guard let token = await account.token() else { toast = "Sign in (Settings) to confirm reports."; return }
        do {
            try await reporter.confirm(alertId: id, vote: v, token: token)
            toast = v == "up" ? "Thanks, confirmed." : "Thanks, marked as gone."
            DriveLog.note("confirm \(v) from banner: \(id)")
        } catch {
            toast = Connectivity.isOffline(error) ? "No signal: the vote did not go through." : "Could not record that."
        }
    }

    /// The limit to show: the trip's own while navigating, else the posted one.
    var limitKmh: Double? {
        if state.isNavigating, let m = core.annotation?.speedLimit { return m.converted(to: .kilometersPerHour).value }
        return state.isNavigating ? nil : postedLimitKmh
    }

    private func setDriving(_ on: Bool) {
        driving = on
        speechWarmth()
        DriveLog.note(on ? "driving mode on" : "driving mode off")
        applyIdleTimer()
        if !on { postedLimitKmh = nil }
        guard case .browsing = state else { return }
        // Only when the map is still on the driver: a map that was
        // panned away is left where it was put.
        switch camera.state {
        case .trackingUserLocation, .trackingUserLocationWithCourse, .trackingUserLocationWithHeading: follow()
        default: break
        }
    }

    func toggleMute() {
        core.spokenInstructionObserver.toggleMute()
        muted = core.spokenInstructionObserver.isMuted
        // One mute for both voices.
        alerts.spoken = prefs.spokenAlerts && !muted
        alerts.muted = muted
    }

    /// The screen stays on while a trip runs or the car is moving, if
    /// the setting says so; a parked phone may sleep.
    private func applyIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = prefs.keepAwake && (state.isNavigating || driving)
    }

    /// Everything drawn over the base map, built once per change and
    /// handed to the overlay, which touches only the parts that changed.
    func overlayScene() -> MapOverlay.Scene {
        let dataKey = "\(markers.stamp)|\(prefs.layersOff)|\(prefs.sourceFilterRaw)|\(sources.directMarkers.count)|\(sources.hidden.sorted().joined(separator: ","))"
        let previewKey: String = {
            guard case .choosing = state, let r = preview else { return "" }
            return "\(r.geometry.count)|\(r.distance)"
        }()
        let pinKey: String = { if case let .found(p) = state { return p.id }; return "" }()
        let ring = alerts.banner(within: prefs.stripAheadMeters)
        let ringKey = ring.map { "\($0.id)|\(Int((($0.alongMeters - alerts.hereAlong) / 50).rounded()))" } ?? ""
        let key = dataKey + "#" + previewKey + "#" + pinKey + "#" + ringKey
        if let c = sceneCache, c.key == key { return c.scene }
        var scene = sceneCache?.scene ?? MapOverlay.Scene()
        if scene.markersVersion != dataKey {
            scene.markers = allMarkers.filter { prefs.isShown($0.kind) && pluginIsOn($0) }.map(MapOverlay.feature(for:))
            scene.markersVersion = dataKey
            let shapes = mapShapes()
            scene.closures = shapes.closures
            scene.tolls = shapes.tolls
            scene.fires = shapes.fires
            scene.shapesVersion = dataKey
        }
        if scene.previewVersion != previewKey {
            scene.preview = previewFeature()
            scene.previewVersion = previewKey
        }
        if scene.pinVersion != pinKey {
            if case let .found(p) = state { scene.pin = p.coordinate } else { scene.pin = nil }
            scene.pinVersion = pinKey
        }
        if scene.alertVersion != ringKey {
            if let r = ring {
                let m = r.marker
                let tint = m.kind == "plugin" ? PluginStyle.color(PluginStyle.sourceId(m)) : (MarkerIcons.color[m.kind] ?? .orange)
                scene.alert = MapOverlay.AlertRing(coordinate: m.coordinate, tint: tint,
                                                   label: Units.distance(max(0, r.alongMeters - alerts.hereAlong)))
            } else {
                scene.alert = nil
            }
            scene.alertVersion = ringKey
        }
        sceneCache = (key, scene)
        return scene
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
