import CoreLocation
import FerrostarCore
import FerrostarCoreFFI
import FerrostarMapLibreUI
import FerrostarSwiftUI
import MapLibre
import MapLibreSwiftDSL
import MapLibreSwiftUI
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .top) {
            DynamicallyOrientingNavigationView(
                styleURL: Backend.styleURL,
                camera: $model.camera,
                navigationState: model.coreState,
                isMuted: model.muted,
                onTapMute: { model.toggleMute() },
                onTapExit: { model.stop() },
                makeMapContent: { mapContent }
            )
            .navigationSpeedLimit(speedLimit: model.core.annotation?.speedLimit, speedLimitStyle: .mutcdStyle)
            .navigationViewInnerGrid(topCenter: { topBanner })
            .ignoresSafeArea()

            if !isNavigating {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 8) {
                        SearchBar()
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape.fill")
                                .padding(11)
                                .background(.regularMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    Spacer()
                }
            }

            VStack {
                Spacer()
                bottomCard
            }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var isNavigating: Bool {
        if case .navigating = model.state { return true }
        return false
    }

    @MapViewContentBuilder private var mapContent: [StyleLayerDefinition] {
        let pin = ShapeSource(identifier: "cs-pin") {
            if case let .found(place) = model.state {
                MLNPointFeature(coordinate: place.coordinate)
            }
        }
        CircleStyleLayer(identifier: "cs-pin-ring", source: pin)
            .radius(14).color(UIColor(red: 0.18, green: 0.5, blue: 0.97, alpha: 0.25))
        CircleStyleLayer(identifier: "cs-pin", source: pin)
            .radius(7).color(UIColor(red: 0.18, green: 0.5, blue: 0.97, alpha: 1))
            .strokeWidth(2).strokeColor(.white)
    }

    @ViewBuilder private var topBanner: some View {
        if case .navigating = model.state, let next = model.alerts.ahead.first {
            NavigationUIBanner(severity: .info) {
                Text("\(next.marker.displayTitle) in \(Units.distance(max(0, next.alongMeters - currentAlong)))")
                    .lineLimit(2)
            }
        } else if model.coreState?.isCalculatingNewRoute == true {
            NavigationUIBanner(severity: .loading) { Text("Rerouting") }
        }
    }

    private var currentAlong: Double {
        guard let loc = model.coreState?.preferredUserLocation?.clLocation.coordinate,
              case .navigating = model.state,
              let geometry = model.coreState?.routeGeometry, geometry.count > 1 else { return 0 }
        let pts = geometry.map(\.clLocationCoordinate2D)
        return AlertsEngine.along(pts, AlertsEngine.cumulativeDistances(pts), loc).along
    }

    @ViewBuilder private var bottomCard: some View {
        switch model.state {
        case .browsing:
            EmptyView()
        case let .found(place):
            PlaceCard(place: place)
        case .routing:
            HStack(spacing: 10) { ProgressView(); Text("Finding routes") }
                .padding(16).frame(maxWidth: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(12)
        case let .choosing(routes, place):
            RoutesCard(routes: routes, place: place)
        case .navigating:
            EmptyView()
        }
    }
}

/// The pin's card: what it is, how far, Navigate, Save as Home, Work or a star.
struct PlaceCard: View {
    @EnvironmentObject var model: AppModel
    let place: Place

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.shortName).font(.headline)
                    Text(place.name).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    if let here = model.here {
                        Text(Units.distance(AlertsEngine.meters(here, place.coordinate)) + " away")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { model.clearFound() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
            HStack(spacing: 8) {
                Button { Task { await model.routes(to: place) } } label: {
                    Label("Navigate", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                Menu {
                    Button("Save as Home") { model.places.set(.home, name: place.name, coordinate: place.coordinate) }
                    Button("Save as Work") { model.places.set(.work, name: place.name, coordinate: place.coordinate) }
                    Button("Save to favorites") { model.places.set(.saved, name: place.name, coordinate: place.coordinate) }
                } label: {
                    Image(systemName: "star").padding(.vertical, 10).padding(.horizontal, 14)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(12)
    }
}

/// The alternatives, fastest first, one tap to go.
struct RoutesCard: View {
    @EnvironmentObject var model: AppModel
    let routes: [Route]
    let place: Place
    @State private var chosen = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("To \(place.shortName)").font(.headline)
                Spacer()
                Button { model.state = .found(place) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
            ForEach(Array(routes.enumerated()), id: \.offset) { i, route in
                let seconds = route.steps.reduce(0) { $0 + $1.duration }
                Button { chosen = i } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(i == 0 ? "Fastest" : "Alternate \(i)").font(.subheadline.weight(.semibold))
                            Text("\(Units.duration(seconds)), \(Units.distance(route.distance))" +
                                 (roadName(route).map { ", via \($0)" } ?? ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if i == chosen { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                    }
                    .padding(10)
                    .background(i == chosen ? Color.accentColor.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            Button { model.start(routes[chosen], to: place) } label: {
                Label("Start", systemImage: "location.north.line.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(12)
    }

    private func roadName(_ route: Route) -> String? {
        route.steps.max { $0.distance < $1.distance }?.roadName?.trimmingCharacters(in: .whitespaces)
            .split(separator: ";").first.map(String.init)
    }
}

struct SettingsSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var miles = Units.useMiles

    var body: some View {
        NavigationStack {
            Form {
                Section("Distances") {
                    Picker("Units", selection: $miles) {
                        Text("Miles").tag(true)
                        Text("Kilometers").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: miles) { v in Units.useMiles = v }
                }
                Section("Alerts") {
                    Toggle("Speak alerts along the route", isOn: Binding(
                        get: { model.alerts.spoken }, set: { model.alerts.spoken = $0 }))
                }
                Section("Places") {
                    if let home = model.places.home { row("Home", home) }
                    if let work = model.places.work { row("Work", work) }
                    ForEach(model.places.saved) { p in row("Saved", p) }
                    if model.places.places.isEmpty { Text("Search a place, then save it as Home, Work or a favorite.").foregroundStyle(.secondary) }
                }
                #if DEBUG
                Section("Testing") {
                    Toggle("Simulate driving the route", isOn: $model.simulating)
                }
                #endif
                Section("About") {
                    LabeledContent("Version", value: AppInfo.version)
                    Link("Data sources", destination: URL(string: "https://commutescout.com/data-sources")!)
                    Link("Privacy", destination: URL(string: "https://commutescout.com/privacy")!)
                    Text("Map tiles and routing by Stadia Maps, data (c) OpenStreetMap contributors. Road data from the agencies listed on commutescout.com. Verify before you drive.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func row(_ label: String, _ p: Place) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Text(p.shortName).lineLimit(1)
            Spacer()
            Button(role: .destructive) { model.places.remove(p) } label: { Image(systemName: "trash") }
        }
    }
}
