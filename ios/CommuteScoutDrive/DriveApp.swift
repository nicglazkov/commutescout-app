import CoreLocation
import MapLibre
import SwiftUI

@main
struct DriveApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(model.prefs.theme.colorScheme)
                .task { await AutoDrive.runIfAsked(model) }
        }
    }
}

/// A scripted drive for automated testing in the simulator: launch
/// with -csAutoDrive and the app searches a place, fetches routes and
/// starts navigating the first one with simulated movement. Debug
/// builds only; release builds ignore the argument.
enum AutoDrive {
    @MainActor static func runIfAsked(_ model: AppModel) async {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-csResetPlaces") { model.places.removeAll() }
        if args.contains("-csSimulate") { model.simulating = true }
        if args.contains("-csFocusMarker") {
            // Center on the closest live marker so a UI test can tap it.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            let here = CLLocationCoordinate2D(latitude: 37.3382, longitude: -121.8863)
            if let all = try? await LiveData.markers(in: (37.0, -122.4, 37.7, -121.5)),
               let m = all.min(by: { AlertsEngine.meters($0.coordinate, here) < AlertsEngine.meters($1.coordinate, here) }) {
                model.markers.view(bounds: MLNCoordinateBounds(
                    sw: CLLocationCoordinate2D(latitude: m.lat - 0.02, longitude: m.lon - 0.02),
                    ne: CLLocationCoordinate2D(latitude: m.lat + 0.02, longitude: m.lon + 0.02)), zoom: 15, kinds: LiveData.kinds)
                model.camera = .center(m.coordinate, zoom: 16, pitch: 0, direction: 0)
            }
            return
        }
        guard args.contains("-csAutoDrive") else { return }
        model.simulating = true
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let place = Place(name: "Los Altos, CA", coordinate: CLLocationCoordinate2D(latitude: 37.372, longitude: -122.110), kind: .recent)
        model.show(place)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await model.routes(to: place)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if case let .choosing(routes, p) = model.state, let first = routes.first {
            model.start(first, to: p)
        }
        #endif
    }
}
