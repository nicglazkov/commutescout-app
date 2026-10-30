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
            if phase == .background { model.pauseIfIdle() }
            if phase == .active {
                // A voice may have been downloaded or deleted in the meantime.
                Voice.refresh()
                model.resumeFromBackground()
            }
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
                DriveLog.note("remote start requested, via \(model.via.count) point(s)")
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
        // "-csOpenAlert kind,lat,lon[,id[,title]]" acts as a tapped watch
        // alert, so the alert sheet can be tried without sending a push.
        if let i = all.firstIndex(of: "-csOpenAlert"), i + 1 < all.count {
            let p = all[i + 1].split(separator: ",", maxSplits: 4).map(String.init)
            if p.count >= 3, let lat = Double(p[1]), let lon = Double(p[2]) {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                AlertInbox.shared.deliver(AlertRef(
                    id: p.count > 3 ? p[3] : nil, kind: AlertRef.markerKind(p[0]), lat: lat, lon: lon,
                    title: p.count > 4 ? p[4] : nil, body: nil, watch: "Test area",
                    sentAt: Date().addingTimeInterval(-600)))
            }
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
                model.select(m)
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
        let place = Place(name: "Palo Alto, CA", coordinate: CLLocationCoordinate2D(latitude: 37.442, longitude: -122.143), kind: .recent)
        model.show(place)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await model.routes(to: place)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if case let .choosing(routes, p) = model.state, let first = routes.first {
            model.start(first, to: p)
        }
        await DebugScenes.run(model, args)
        #endif
    }
}

#if DEBUG
/// Screenshot scenes for a simulated drive (debug builds only):
/// "-cs3D" starts in 3D, "-csForceAlert kind[,meters]" puts a made-up
/// event of that kind on the route ahead, "-csSeeMore" opens it, and
/// "-csClearing" makes it vanish so the cleared state shows.
enum DebugScenes {
    @MainActor static func run(_ model: AppModel, _ args: [String]) async {
        if args.contains("-cs3D"), !model.prefs.is3D { model.toggle3D() }
        guard let i = args.firstIndex(of: "-csForceAlert"), i + 1 < args.count else { return }
        let parts = args[i + 1].split(separator: ",").map(String.init)
        let meters = parts.count > 1 ? Double(parts[1]) ?? 1300 : 1300
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard let m = marker(parts[0]) else { return }
        model.alerts.debugAdd(m, meters: meters)
        if args.contains("-csClearing") {
            model.alerts.clearedHold = 20
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            model.alerts.debugVanish()
        }
    }

    static func marker(_ kind: String) -> RoadMarker? {
        let four = #"{"total":4,"lanes":[{"n":1,"type":"general","state":"open"},{"n":2,"type":"general","state":"open"},{"n":3,"type":"general","state":"open"},{"n":4,"type":"general","state":"closed"}],"target":3,"basis":"feed"}"#
        let base = #""lat":37.442,"lon":-122.143,"id":"debug-\#(kind)""#
        let json: String
        switch kind {
        case "crash": json = #"{"kind":"incident",\#(base),"type":"Traffic Collision","label":"Crash","location":"US-101 S at University Ave","lanes":"right lane blocked","lane_layout":\#(four)}"#
        case "closure": json = #"{"kind":"lane_closure",\#(base),"label":"Two right lanes closed","lanes":"2 right lanes closed"}"#
        case "hazard": json = #"{"kind":"incident",\#(base),"type":"Traffic Hazard","label":"Object on road","lanes":"left lane"}"#
        case "police": json = #"{"kind":"plugin",\#(base),"flare_kind":"police","label":"Police reported","source":"waze","road":"US-101 S"}"#
        case "jam": json = #"{"kind":"incident",\#(base),"type":"Slow traffic","label":"Slow traffic"}"#
        case "chain": json = #"{"kind":"chain_control",\#(base),"label":"Chain control R-2","status":"R2"}"#
        case "fire": json = #"{"kind":"wildfire",\#(base),"name":"Oak Fire","acres":1240,"contained":35}"#
        case "ice": json = #"{"kind":"rwis",\#(base),"station":"Summit Rd","pave_c":-0.5,"air_c":1.1}"#
        case "sign": json = #"{"kind":"sign",\#(base),"label":"Message sign","lines":["SAN JOSE 24 MIN","SFO 18 MIN"]}"#
        case "camera": json = #"{"kind":"incident",\#(base),"type":"Speed camera","label":"Speed camera"}"#
        case "toll": json = #"{"kind":"toll",\#(base),"label":"Express lanes","min":4.5,"max":4.5}"#
        default: return nil
        }
        return try? JSONDecoder().decode(RoadMarker.self, from: Data(json.utf8))
    }
}
#endif
