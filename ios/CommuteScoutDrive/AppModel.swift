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
}

@MainActor
final class AppModel: ObservableObject {
    @Published var state: DriveState = .browsing
    @Published var camera: MapViewCamera = .default()
    @Published var coreState: NavigationState?
    @Published var errorMessage: String?
    @Published var muted = false
    @Published var simulating = false { didSet { location.simulate = simulating } }

    let core: FerrostarCore
    let location = LocationSource()
    let places = PlaceStore()
    let alerts = AlertsEngine()
    private let delegate = NavDelegate()
    private var cancellables = Set<AnyCancellable>()

    init() {
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
        let provider = try! WellKnownRouteProvider.valhalla(
            endpointUrl: Backend.navRouteURL.absoluteString, profile: "auto")
            .withJsonOptions(options: ["units": Units.useMiles ? "miles" : "kilometers"])
        // A bad provider is a programming error, not a runtime condition.
        core = try! FerrostarCore(
            wellKnownRouteProvider: provider,
            locationProvider: location,
            navigationControllerConfig: config,
            annotation: AnnotationPublisher<ValhallaExtendedOSRMAnnotation>.valhallaExtendedOSRM()
        )
        core.delegate = delegate
        core.$state.receive(on: DispatchQueue.main).sink { [weak self] s in
            self?.coreState = s
            if let loc = s?.preferredUserLocation?.clLocation.coordinate {
                self?.alerts.update(position: loc)
            }
        }.store(in: &cancellables)
        location.startUpdating()
        camera = .center(CLLocationCoordinate2D(latitude: 37.5, longitude: -121.9), zoom: 8)
        Task { await followOnceAllowed() }
    }

    /// Follow the driver as soon as location is allowed (the first launch
    /// asks for permission, so this waits for the answer).
    private func followOnceAllowed() async {
        for _ in 0 ..< 120 {
            if location.enabled {
                if case .browsing = state { follow() }
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    /// Keep the map on the driver, north up, like a maps app at rest.
    func follow() {
        camera = .trackUserLocation(zoom: 14)
    }

    var here: CLLocationCoordinate2D? { location.lastLocation?.clLocation.coordinate }

    // MARK: browsing

    func show(_ place: Place) {
        state = .found(place)
        camera = .center(place.coordinate, zoom: 14)
    }

    func clearFound() {
        if case .found = state { state = .browsing }
    }

    // MARK: routes

    func routes(to place: Place) async {
        guard let from = here else {
            errorMessage = "Waiting for your location."
            return
        }
        state = .routing
        do {
            let found = try await core.getRoutes(
                initialLocation: UserLocation(clCoordinateLocation2D: from),
                waypoints: [Waypoint(coordinate: GeographicCoordinate(cl: place.coordinate), kind: .break)])
            guard !found.isEmpty else { throw DriveError.noRoute }
            state = .choosing(found, place)
            camera = .default()
            if let bbox = found.first?.bbox {
                camera = .boundingBox(MLNCoordinateBounds(
                    sw: bbox.sw.clLocationCoordinate2D, ne: bbox.ne.clLocationCoordinate2D),
                    edgePadding: .init(top: 120, left: 40, bottom: 320, right: 40))
            }
        } catch {
            errorMessage = error.localizedDescription
            state = .found(place)
        }
    }

    func start(_ route: Route, to place: Place) {
        do {
            if simulating { try location.simulate(route: route) }
            try core.startNavigation(route: route)
            places.noteRecent(name: place.name, coordinate: place.coordinate)
            alerts.start(route: route.geometry.map(\.clLocationCoordinate2D))
            camera = .automotiveNavigation()
            state = .navigating(place)
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        core.stopNavigation()
        alerts.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        state = .browsing
        follow()
    }

    func toggleMute() {
        core.spokenInstructionObserver.toggleMute()
        muted = core.spokenInstructionObserver.isMuted
        alerts.spoken = !muted
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
    func core(_: FerrostarCore, didStartWith _: Route) {}

    func core(_: FerrostarCore, correctiveActionForDeviation _: DeviationKind,
              remainingWaypoints waypoints: [Waypoint]) -> CorrectiveAction {
        .getNewRoutes(waypoints: waypoints)
    }

    func core(_ core: FerrostarCore, loadedAlternateRoutes routes: [Route]) {
        guard core.state?.isCalculatingNewRoute ?? false, let route = routes.first else { return }
        try? core.startNavigation(route: route)
    }
}

extension CLLocationCoordinate2D {
    var pretty: String { String(format: "%.5f, %.5f", latitude, longitude) }
}
