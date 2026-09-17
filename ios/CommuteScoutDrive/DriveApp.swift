import CoreLocation
import SwiftUI

@main
struct DriveApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
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
        guard ProcessInfo.processInfo.arguments.contains("-csAutoDrive") else { return }
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
