import CoreLocation
import MapLibre
import SwiftUI

@main
struct DriveApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(model.prefs.theme.colorScheme)
                .task { await AutoDrive.runIfAsked(model) }
        }
        .onChange(of: scenePhase) { phase in
            DriveLog.note("app \(phase == .active ? "active" : phase == .background ? "background" : "inactive")")
        }
    }
}

/// A scripted drive for automated testing in the simulator: launch
/// with -csAutoDrive and the app searches a place, fetches routes and
/// starts navigating the first one with simulated movement. Debug
/// builds only; release builds ignore the argument.
enum AutoDrive {
    @MainActor static func runIfAsked(_ model: AppModel) async {
        // Any build: "-csNavigateTo lat,lon,Name" starts a real route from the
        // phone's own position, so a drive can be started from a paired Mac.
        let all = ProcessInfo.processInfo.arguments
        if let i = all.firstIndex(of: "-csNavigateTo"), i + 1 < all.count {
            let parts = all[i + 1].split(separator: ",", maxSplits: 2).map(String.init)
            if parts.count >= 2, let lat = Double(parts[0]), let lon = Double(parts[1]) {
                let place = Place(name: parts.count > 2 ? parts[2] : all[i + 1],
                                  coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), kind: .recent)
                DriveLog.note("remote start requested: \(place.name)")
                for _ in 0 ..< 30 where model.here == nil { try? await Task.sleep(nanoseconds: 1_000_000_000) }
                model.show(place)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await model.routes(to: place)
                if case let .choosing(routes, p) = model.state, let first = routes.first {
                    model.start(first, to: p)
                } else {
                    DriveLog.note("remote start: no route (state \(model.state))")
                }
            }
            return
        }
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-csResetPlaces") { model.places.removeAll() }
        if args.contains("-csResetPrefs") {
            let d = UserDefaults.standard
            for k in d.dictionaryRepresentation().keys where k.hasPrefix("cs.") && k != "cs.places.v1" { d.removeObject(forKey: k) }
            model.prefs.objectWillChange.send()
        }
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
