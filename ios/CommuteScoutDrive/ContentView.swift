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
    @Environment(\.colorScheme) private var colorScheme
    // "-csOpenSettings" opens Settings at launch, for screenshots and tests.
    @State private var showSettings = ProcessInfo.processInfo.arguments.contains("-csOpenSettings")
    @State private var showLayers = false
    @State private var showReport = false
    @State private var showTools = false

    var body: some View {
        ZStack(alignment: .top) {
            // The navigation view owns the safe area: the maneuver card
            // and the trip bar clear the island and the home indicator.
            DynamicallyOrientingNavigationView(
                styleURL: model.styleURL,
                camera: $model.camera,
                navigationCamera: model.navigationCamera,
                navigationState: model.coreState,
                isMuted: model.muted,
                onTapMute: { model.toggleMute() },
                onTapExit: { model.stop() },
                makeMapContent: { mapContent }
            )
            .navigationViewInnerGrid(topCenter: {
                // The grid's middle column is narrow; the banner takes
                // the width the instruction card has.
                VStack(spacing: 8) {
                    reroutingBanner
                    alertBanner
                }
                .frame(width: UIScreen.main.bounds.width - 24)
            })

            MapHook(
                // A closure stretch and a toll corridor answer a tap the
                // same way their dot does, which is what the website does.
                layerIds: MapOverlay.tappable,
                scene: model.overlayScene(),
                trafficTiles: model.prefs.traffic ? Backend.trafficTiles : nil,
                onTap: { _, keys in
                    if let k = keys.first { model.showMarker(key: k) } else if model.selectedMarker != nil { model.clearMarker() }
                },
                onLongPress: { coord in if !isNavigating { model.dropPin(at: coord) } },
                onView: { bounds, zoom, heading, center in
                    model.heading = heading
                    model.viewCenter = center
                    model.viewZoom = zoom
                    model.markers.view(bounds: bounds, zoom: zoom, kinds: model.prefs.apiKinds)
                    model.sources.view(center: center)
                }
            )
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)

            if !isNavigating {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 8) {
                        SearchBar()
                        VStack(spacing: 8) {
                            Button { showSettings = true } label: { roundIcon("gearshape.fill") }
                                .accessibilityIdentifier("settings")
                            Button { showTools = true } label: { roundIcon("line.3.horizontal") }
                                .accessibilityIdentifier("tools")
                            Button { model.toggle3D() } label: { roundText(model.prefs.is3D ? "2D" : "3D") }
                                .accessibilityIdentifier("perspective")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    if let n = model.offlineNotice {
                        OfflineBanner(title: n.title, detail: n.detail)
                            .padding(.horizontal, 12).padding(.top, 8)
                    }
                    alertBanner.padding(.horizontal, 12).padding(.top, 8)
                    Spacer()
                }
            }

            // Map controls: 2D/3D, compass when turned, my location. While
            // navigating Ferrostar draws its own zoom and recenter buttons.
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    Spacer()
                    VStack(spacing: 8) {
                        if !isNavigating, abs(model.heading) > 1 {
                            Button { model.faceNorth() } label: { compass }
                                .accessibilityIdentifier("compass")
                        }
                        if isNavigating {
                            // Browsing has this under the menu button; on a
                            // trip the top belongs to the instruction card.
                            Button { model.toggle3D() } label: { roundText(model.prefs.is3D ? "2D" : "3D") }
                                .accessibilityIdentifier("perspective")
                        }
                        if !isNavigating {
                            Button { model.follow() } label: { roundIcon("location.fill") }
                                .accessibilityIdentifier("locate")
                        }
                        // Report, like Waze: one tap from anywhere, big enough
                        // to hit at a glance from the wheel.
                        Button { if model.reportCoordinate != nil { showReport = true } } label: {
                            VStack(spacing: 1) {
                                Image(systemName: "exclamationmark.bubble.fill")
                                    .font(.system(size: 26, weight: .semibold))
                                Text("Report").font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(Color.orange, in: Circle())
                            .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
                        }
                        .accessibilityIdentifier("report")
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, isNavigating ? 118 : bottomCardHeight + 12)
                }
            }

            // The speedometer sits above the trip bar, left of the side
            // buttons: clear of the instruction card whatever its height.
            if model.prefs.showSpeedLimit, model.speedMps >= 0 || isNavigating {
                VStack {
                    Spacer()
                    HStack {
                        Speedometer(speedMps: model.speedMps, limitKmh: model.limitKmh)
                        Spacer()
                    }
                    .padding(.leading, 12).padding(.bottom, isNavigating ? 124 : bottomCardHeight + 12)
                }
            }
            VStack {
                Spacer()
                bottomCard
            }
        }
        .onAppear { model.isDark = colorScheme == .dark }
        .onChange(of: colorScheme) { s in model.isDark = s == .dark }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .sheet(isPresented: $showLayers) { LayersSheet().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showTools) { ToolsSheet(showLayers: $showLayers).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showReport) {
            if let c = model.reportCoordinate { ReportSheet(coordinate: c).presentationDetents([.large]) }
        }
        .overlay(alignment: .top) {
            if let t = model.toast {
                Text(t).font(.subheadline).padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule()).padding(.top, 64)
                    .task { try? await Task.sleep(nanoseconds: 2_500_000_000); model.toast = nil }
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var isNavigating: Bool { model.state.isNavigating }

    /// Roughly how tall the bottom card is, so the map buttons sit above it.
    private var bottomCardHeight: CGFloat {
        if let m = model.selectedMarker {
            // A camera shows a picture and a toll shows its rates, so
            // both cards are taller than the rest.
            switch m.kind {
            case "camera": return 350
            case "toll": return 330
            case "sign", "rwis": return 260
            default: return 170
            }
        }
        switch model.state {
        case .browsing: return model.resumable == nil ? 0 : 140
        case .found: return 150
        case .routing: return 80
        case .choosing: return 330
        case .navigating: return 0
        }
    }

    private func roundIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 22, height: 22)
            .padding(11)
            .background(.regularMaterial, in: Circle())
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    private func roundText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .bold))
            .frame(width: 22, height: 22)
            .padding(11)
            .background(.regularMaterial, in: Circle())
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    private var compass: some View {
        Image(systemName: "location.north.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.red)
            .rotationEffect(.degrees(-model.heading))
            .frame(width: 22, height: 22)
            .padding(11)
            .background(.regularMaterial, in: Circle())
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    /// Nothing: everything CommuteScout draws goes through MapOverlay,
    /// because content given to the map view here is removed and added
    /// again on every update, which makes it blink.
    @MapViewContentBuilder private var mapContent: [StyleLayerDefinition] {
        // No DSL layers.
    }

    /// The next alert within the chosen distance: a strip, or a pill when
    /// tucked away. Placed by the navigation view's grid under the
    /// instruction card, so it never overlaps it whatever its height.
    /// The alert ahead, on a trip or driving without one, as a banner
    /// at the top. Nothing when it was swiped away or is behind.
    @ViewBuilder private var alertBanner: some View {
        if let next = model.alerts.banner(within: model.prefs.stripAheadMeters) {
            AlertBanner(item: next, along: model.alerts.hereAlong)
                .animation(.spring(duration: 0.35), value: next.id)
        }
    }

    /// Under the instruction card while navigating: the offline notice
    /// when there is no signal (a reroute cannot happen then, and saying
    /// "Rerouting" would be a promise the app cannot keep), otherwise
    /// the reroute in progress.
    @ViewBuilder private var reroutingBanner: some View {
        if let n = model.offlineNotice {
            OfflineBanner(title: n.title, detail: n.detail).padding(.horizontal, 12)
        } else if model.coreState?.isCalculatingNewRoute == true {
            NavigationUIBanner(severity: .loading) { Text("Rerouting") }
        }
    }

    @ViewBuilder private var bottomCard: some View {
        if let m = model.selectedMarker {
            MarkerCard(marker: m)
        } else {
            switch model.state {
            case .browsing:
                if let trip = model.resumable { ResumeCard(trip: trip) }
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
}

/// No signal: what still works, and how old the road reports are.
struct OfflineBanner: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wifi.slash").font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-banner")
    }
}

/// A trip that was running when the app closed: pick it up again, with
/// or without a signal, since guidance only needs the saved route.
struct ResumeCard: View {
    @EnvironmentObject var model: AppModel
    let trip: SavedTrip

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Resume your trip to \(trip.place.shortName)?").font(.headline)
                Text("Started at \(OfflineText.time(trip.startedAt)). Works without a signal.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button { model.resume() } label: {
                    Label("Resume", systemImage: "location.north.line.fill").frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("resume-trip")
                Button("Not now") { model.dismissResume() }
                    .buttonStyle(.bordered).padding(.vertical, 10)
                    .accessibilityIdentifier("dismiss-trip")
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(12)
    }
}

/// The next road event on the route: what it is and how far ahead.
/// Tap to hear it again.
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
                    .accessibilityIdentifier("place-close")
            }
            HStack(spacing: 8) {
                Button { Task { await model.routes(to: place) } } label: {
                    Label("Navigate", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("navigate")
                Menu {
                    Button("Save as Home") { model.places.set(.home, name: place.name, coordinate: place.coordinate) }
                    Button("Save as Work") { model.places.set(.work, name: place.name, coordinate: place.coordinate) }
                    Button("Save to favorites") { model.places.set(.saved, name: place.name, coordinate: place.coordinate) }
                    ShareLink("Share", item: Backend.mapURL(lat: place.lat, lon: place.lon))
                } label: {
                    Image(systemName: "star").padding(.vertical, 10).padding(.horizontal, 14)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("save-menu")
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
                Button { model.state = .found(place); model.preview = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("routes-close")
            }
            ForEach(Array(routes.enumerated()), id: \.offset) { i, route in
                let seconds = route.steps.reduce(0) { $0 + $1.duration }
                Button { chosen = i; model.preview = route } label: {
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
                .accessibilityIdentifier("route-\(i)")
            }
            Button { model.start(routes[chosen], to: place) } label: {
                Label("Start", systemImage: "location.north.line.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("start")
            // The map along the route, for a drive through a dead zone.
            // Saved on its own on Wi-Fi when the trip starts; this is the
            // tap for mobile data, and it says so.
            if model.online, !model.mapFiles.progress.isEmpty {
                ProgressView(value: model.mapFiles.progress.values.first ?? 0) { Text("Saving the map for this trip").font(.caption) }
            } else if model.online, !(Connectivity.shared.onWifi && model.prefs.mapAutoSave) {
                Button { model.saveTripMap(routes[chosen], to: place, manual: true) } label: {
                    Label(Connectivity.shared.onWifi ? "Save the map for this trip" : "Save the map for this trip (mobile data)",
                          systemImage: "arrow.down.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(.tint)
                .accessibilityIdentifier("save-trip-map")
            }
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

/// What the map shows: the same layers as the website's Layers tool.
struct LayersSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Base map") {
                    // The same cards as Settings, so the choice looks the same everywhere.
                    BaseMapCards(choice: Binding(get: { model.prefs.mapStyle }, set: { model.prefs.mapStyle = $0 }), dark: model.isDark)
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    Toggle("Traffic", isOn: Binding(get: { model.prefs.traffic }, set: { model.prefs.traffic = $0; model.objectWillChange.send() }))
                    Toggle("3D perspective", isOn: Binding(get: { model.prefs.is3D }, set: { _ in model.toggle3D() }))
                }
                Section {
                    Picker("Sources", selection: Binding(get: { model.prefs.sourceFilter },
                                                         set: { model.prefs.sourceFilter = $0; model.markers.refresh(force: true) })) {
                        ForEach(Prefs.SourceFilter.allCases) { f in Text(f.label).tag(f) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("source-filter")
                } footer: {
                    Text("Official is agency data. Plugins are the sources you installed from the marketplace.")
                }
                Section("On the road") {
                    ForEach(Prefs.layerKinds, id: \.key) { k in
                        Toggle(isOn: Binding(get: { model.prefs.isChosen(k.key) },
                                             set: { model.prefs.setShown(k.key, $0); model.markers.refresh(force: true) })) {
                            Label { Text(k.label) } icon: {
                                Image(systemName: MarkerIcons.name(k.key)).foregroundStyle(MarkerIcons.tint(k.key))
                            }
                        }
                    }
                    Text("Cameras and toll prices start off, the same as the website. Cameras are the densest layer.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Plugins") {
                    ForEach(model.sources.catalog) { p in
                        Toggle(isOn: Binding(get: { model.sources.isOn(p.id) },
                                             set: { model.sources.setOn(p.id, $0); model.markers.refresh(force: true) })) {
                            Label { Text(p.name).lineLimit(2) } icon: {
                                PluginBadge(sourceId: p.id, category: p.oneCategory, size: 22)
                            }
                        }
                        .accessibilityIdentifier("plugin-switch-\(p.id)")
                    }
                    NavigationLink("My plugins and private sources") { SourcesView() }
                }
                .task { await model.sources.loadCatalog() }
                Section {
                    Link(destination: URL(string: "https://commutescout.com/data-sources")!) {
                        Label("Where this data comes from", systemImage: "safari")
                    }
                }
            }
            .navigationTitle("Layers")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
