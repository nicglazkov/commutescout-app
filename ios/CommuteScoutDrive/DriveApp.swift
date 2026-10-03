import CoreLocation
import MapLibre
import SwiftUI

@main
struct DriveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
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
        #if DEBUG || CS_TEST_HOOKS
        // Debug and Ad Hoc builds (scripts/ios_build.sh device sets
        // CS_TEST_HOOKS): "-csNavigateTo lat,lon,Name" starts a real route
        // from the phone's own position, so a drive can be started from a
        // paired Mac. A TestFlight build ignores the argument.
        let all = ProcessInfo.processInfo.arguments
        if let i = all.firstIndex(of: "-csNavigateTo"), i + 1 < all.count {
            let parts = all[i + 1].split(separator: ",", maxSplits: 2).map(String.init)
            if parts.count >= 2, let lat = Double(parts[0]), let lon = Double(parts[1]) {
                let place = Place(name: parts.count > 2 ? parts[2] : all[i + 1],
                                  coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), kind: .recent)
                if let v = all.firstIndex(of: "-csVia"), v + 1 < all.count {
                    model.via = all[v + 1].split(separator: ";").compactMap { pair in
                        let p = pair.split(separator: ",").map(String.init)
                        guard p.count == 2, let la = Double(p[0]), let lo = Double(p[1]) else { return nil }
                        return CLLocationCoordinate2D(latitude: la, longitude: lo)
                    }
                }
                DriveLog.note("remote start requested: \(place.name), via \(model.via.count) point(s)")
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
        #endif
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-csResetPlaces") { model.places.removeAll() }
        if args.contains("-csResetPrefs") {
            let d = UserDefaults.standard
            for k in d.dictionaryRepresentation().keys where k.hasPrefix("cs.") && k != "cs.places.v1" { d.removeObject(forKey: k) }
            model.prefs.objectWillChange.send()
        }
        if args.contains("-csSimulate") { model.simulating = true }
        // "-csView lat,lon,zoom" puts the camera somewhere, for screenshots.
        if let i = args.firstIndex(of: "-csView"), i + 1 < args.count {
            let p = args[i + 1].split(separator: ",").compactMap { Double($0) }
            if p.count == 3 {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                model.camera = .center(CLLocationCoordinate2D(latitude: p[0], longitude: p[1]), zoom: p[2], pitch: 0, direction: 0)
            }
        }
        // "-csTour" zooms and pans through a set of views, for a recording.
        if args.contains("-csTour") {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            let stops: [(Double, Double, Double)] = [(37.78, -122.42, 13.5), (37.78, -122.42, 11), (37.6, -122.2, 8.5),
                                                      (39, -98, 4.5), (41.88, -87.68, 11.5), (41.88, -87.68, 14)]
            for (lat, lon, z) in stops {
                model.camera = .center(CLLocationCoordinate2D(latitude: lat, longitude: lon), zoom: z, pitch: 0, direction: 0)
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
        // "-csOpenCamera video|still" opens a camera card, for screenshots.
        if let i = args.firstIndex(of: "-csOpenCamera"), i + 1 < args.count {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            let wantVideo = args[i + 1] == "video"
            if let all = try? await LiveData.markers(in: (33.9, -118.4, 34.2, -118.0), kinds: "camera"),
               let m = all.first(where: { ($0.stream != nil) == wantVideo && $0.image != nil && ($0.stream ?? "").contains("CCTV-196") == wantVideo }) {
                model.camera = .center(m.coordinate, zoom: 15, pitch: 0, direction: 0)
                model.selectedMarker = m
            }
        }
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
