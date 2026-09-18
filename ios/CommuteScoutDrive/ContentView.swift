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
    @State private var showSettings = false
    @State private var showLayers = false
    @State private var showReport = false
    @State private var showTools = false
    @State private var stripCollapsed = false

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
            .navigationSpeedLimit(speedLimit: model.prefs.showSpeedLimit ? model.core.annotation?.speedLimit : nil,
                                  speedLimitStyle: .mutcdStyle)
            .navigationViewInnerGrid(topCenter: { reroutingBanner })

            MapHook(
                layerIds: Set(MarkerIcons.kinds.map { "cs-m-\($0)" }),
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
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
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
                        Button { model.toggle3D() } label: { roundText(model.prefs.is3D ? "2D" : "3D") }
                            .accessibilityIdentifier("perspective")
                        if !isNavigating {
                            Button { model.follow() } label: { roundIcon("location.fill") }
                                .accessibilityIdentifier("locate")
                        }
                        // Report, like Waze: one tap from anywhere.
                        Button { if model.reportCoordinate != nil { showReport = true } } label: {
                            Image(systemName: "exclamationmark.bubble.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .padding(13)
                                .background(Color.orange, in: Circle())
                                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                        }
                        .accessibilityIdentifier("report")
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, isNavigating ? 118 : bottomCardHeight + 12)
                }
            }

            // The next alert sits above the trip bar, left of the side
            // buttons: clear of the instruction card whatever its height.
            VStack {
                Spacer()
                alertStripOrPill
                    .padding(.leading, 12).padding(.trailing, 76).padding(.bottom, 124)
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
        if model.selectedMarker != nil { return 170 }
        switch model.state {
        case .browsing: return 0
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

    @MapViewContentBuilder private var mapContent: [StyleLayerDefinition] {
        // Live road markers, one layer per kind so each has its icon.
        let markers = ShapeSource(identifier: "cs-markers") {
            for m in model.allMarkers where model.prefs.isShown(m.kind) && model.sources.isOn(m.source ?? "") {
                let f = MLNPointFeature(coordinate: m.coordinate)
                f.attributes = ["key": m.key, "kind": m.kind]
                f
            }
        }
        for kind in MarkerIcons.kinds {
            SymbolStyleLayer(identifier: "cs-m-\(kind)", source: markers)
                .iconImage(MarkerIcons.images[kind]!)
                .iconAllowsOverlap(true)
                .predicate(NSPredicate(format: "kind == %@", kind))
        }
        // The alternative under consideration, drawn like the navigation route.
        let line = ShapeSource(identifier: "cs-route") {
            if let f = model.previewFeature() { f }
        }
        LineStyleLayer(identifier: "cs-route-border", source: line)
            .lineColor(UIColor(red: 0.11, green: 0.31, blue: 0.66, alpha: 1)).lineWidth(9)
            .lineCap(.round).lineJoin(.round)
        LineStyleLayer(identifier: "cs-route", source: line)
            .lineColor(UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1)).lineWidth(6)
            .lineCap(.round).lineJoin(.round)
        // The pin.
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

    /// The next alert within the chosen distance: a strip, or a pill when
    /// tucked away. Placed by the navigation view's grid under the
    /// instruction card, so it never overlaps it whatever its height.
    @ViewBuilder private var alertStripOrPill: some View {
        if isNavigating, let next = model.alerts.ahead.first,
           next.alongMeters - model.alerts.hereAlong <= model.prefs.stripAheadMeters {
            if stripCollapsed {
                // Tucked away: a pill with the icon and distance; tap to bring it back.
                HStack {
                    Spacer()
                    Button { withAnimation { stripCollapsed = false } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: MarkerIcons.name(next.marker.kind)).foregroundStyle(MarkerIcons.tint(next.marker.kind))
                            Text(Units.distance(max(0, next.alongMeters - model.alerts.hereAlong))).font(.caption.weight(.semibold))
                            if model.alerts.ahead.count > 1 { Text("+\(model.alerts.ahead.count - 1)").font(.caption2).foregroundStyle(.secondary) }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    }
                    .accessibilityIdentifier("alert-pill")
                }
                .padding(.horizontal, 12)
            } else {
                AlertStrip(item: next, along: model.alerts.hereAlong, onCollapse: { withAnimation { stripCollapsed = true } })
                    .padding(.horizontal, 12)
            }
        }

    }

    @ViewBuilder private var reroutingBanner: some View {
        if model.coreState?.isCalculatingNewRoute == true {
            NavigationUIBanner(severity: .loading) { Text("Rerouting") }
        }
    }

    @ViewBuilder private var bottomCard: some View {
        if let m = model.selectedMarker {
            MarkerCard(marker: m)
        } else {
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
}

/// The next road event on the route: what it is and how far ahead.
/// Tap to hear it again.
struct AlertStrip: View {
    @EnvironmentObject var model: AppModel
    let item: AlertsEngine.Upcoming
    let along: Double
    var onCollapse: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: MarkerIcons.name(item.marker.kind)).font(.title3).foregroundStyle(MarkerIcons.tint(item.marker.kind))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.marker.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text("in \(Units.distance(max(0, item.alongMeters - along)))" +
                     (model.alerts.ahead.count > 1 ? ", \(model.alerts.ahead.count - 1) more ahead" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let onCollapse {
                Button(action: onCollapse) {
                    Image(systemName: "chevron.up").font(.caption.weight(.bold)).foregroundStyle(.secondary).padding(6)
                }
                .accessibilityIdentifier("alert-collapse")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .onTapGesture { model.alerts.say(item.marker) }
        .accessibilityIdentifier("alert-strip")
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
                    Picker("Style", selection: Binding(get: { model.prefs.mapStyle }, set: { model.prefs.mapStyle = $0 })) {
                        ForEach(Prefs.MapStyle.allCases) { s in Text(s.label).tag(s) }
                    }
                    .pickerStyle(.inline).labelsHidden()
                    Toggle("Traffic", isOn: Binding(get: { model.prefs.traffic }, set: { model.prefs.traffic = $0; model.objectWillChange.send() }))
                    Toggle("3D perspective", isOn: Binding(get: { model.prefs.is3D }, set: { _ in model.toggle3D() }))
                }
                Section("On the road") {
                    ForEach(Prefs.layerKinds, id: \.key) { k in
                        Toggle(isOn: Binding(get: { model.prefs.isShown(k.key) },
                                             set: { model.prefs.setShown(k.key, $0); model.markers.refresh(force: true) })) {
                            Label { Text(k.label) } icon: {
                                Image(systemName: MarkerIcons.name(k.key)).foregroundStyle(MarkerIcons.tint(k.key))
                            }
                        }
                    }
                }
                Section {
                    NavigationLink("Community sources (Flare plugins)") { SourcesView() }
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
