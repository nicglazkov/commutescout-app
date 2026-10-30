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
    /// The first run, once ("-csWelcome" shows it for screenshots).
    @State private var showWelcome = Prefs.welcomeIsDue
    // "-csOpenMore market|plugin|offline|picker|savedmap" opens that page at launch (debug builds).
    @State private var moreScreen: String? = OfflineLaunch.wanted
    @State private var showLayers = false
    @State private var showReport = false
    @State private var showTools = false
    /// The event panel's height as laid out, so the map buttons sit above it.
    @State private var panelHeight: CGFloat = 0
    @State private var browseAlertMore = false
    /// The room the map makes under a tucked alert, eased in and out.
    @StateObject private var room = CameraRoomAnimator()

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
            // On a trip the side buttons and the speed disc live in the
            // navigation view's own grid, so they never sit on its zoom
            // and recenter buttons or under the maneuver card.
            // The puck sits lower while an alert is tucked under the
            // card, so the road ahead shows below both (2D and 3D).
            .navigationMapViewContentInset(NavigationMapViewContentInsetBundle(
                portrait: { [room = room.value] g in .portrait(within: g, minHeight: CameraRoom.minHeight(room: room)) }))
            // App messages ride under the maneuver card (DriveTop).
            .navigationViewInnerGrid(topCenter: { EmptyView() }, bottomLeading: {
                if isNavigating, model.prefs.showSpeedLimit { SpeedDisc(speedMps: model.speedMps, limitKmh: model.limitKmh) }
            }, bottomTrailing: {
                // Ferrostar draws this grid while browsing too; the browse
                // column owns these controls then.
                if isNavigating { VStack(spacing: 10) {
                    DGModesPill(is3D: model.prefs.is3D) { withAnimation(DG.tilt) { model.toggle3D() } }
                    DGReportButton { if model.reportCoordinate != nil { showReport = true } }
                        .accessibilityIdentifier("report")
                } }
            })
            // Day Glass+: the maneuver card with the alert tucked under
            // it, the trip bar, and no road-name pill (the card says it).
            .navigationViewInstructionView { state, _, size in DriveTop(state: state, size: size) }
            .navigationViewProgressView { state, exit in TripBar(state: state, onExit: exit) }
            .navigationViewCurrentRoadView { _ in EmptyView() }

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

            if !isNavigating, let t = clearedWatch {
                // A cleared watch alert says so where the search bar was.
                WatchClearedCapsule(text: t.text)
                    .padding(.horizontal, 12).padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if !isNavigating && !showWelcome {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 8) {
                        SearchBar()
                        VStack(spacing: 10) {
                            DGRoundButton(size: 52) { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                                .accessibilityLabel("Settings")
                                .accessibilityIdentifier("settings")
                            DGRoundButton(size: 52) { showTools = true } label: { Image(systemName: "square.grid.2x2.fill") }
                                .accessibilityLabel("Tools")
                                .accessibilityIdentifier("tools")
                            DGModesPill(is3D: model.prefs.is3D) { withAnimation(DG.tilt) { model.toggle3D() } }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    if let n = model.offlineNotice {
                        OfflineBanner(title: n.title, detail: n.detail)
                            .padding(.horizontal, 12).padding(.top, 8)
                    }
                    if !isNavigating { alertBanner.padding(.horizontal, 12).padding(.top, 8) }
                    Spacer()
                }
            }

            // Map controls: 2D/3D, compass when turned, my location. While
            // navigating Ferrostar draws its own zoom and recenter buttons.
            if !isNavigating && !showWelcome { VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    Spacer()
                    VStack(spacing: 8) {
                        if !isNavigating, abs(model.heading) > 1 {
                            Button { model.faceNorth() } label: { compass }
                                .accessibilityIdentifier("compass")
                        }
                        if !isNavigating {
                            DGRoundButton { showLayers = true } label: { Image(systemName: "square.3.layers.3d") }
                                .accessibilityLabel("Map layers")
                                .accessibilityIdentifier("layers")
                            DGRoundButton { model.follow() } label: { Image(systemName: "location.fill") }
                                .accessibilityLabel("My location")
                                .accessibilityIdentifier("locate")
                        }
                        // Report, like Waze: one tap from anywhere, big enough
                        // to hit at a glance from the wheel.
                        DGReportButton { if model.reportCoordinate != nil { showReport = true } }
                            .accessibilityIdentifier("report")
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, bottomCardHeight + 12)
                }
            } }

            // Above the trip bar, left of the side buttons, clear of the
            // instruction card whatever its height: on a trip the alert
            // banner, then the speedometer under it. (Browsing shows the
            // banner at the top instead, under the search bar.)
            VStack {
                Spacer()
                // On a trip the alert rides under the maneuver card.
                if model.prefs.showSpeedLimit, model.speedMps >= 0, !isNavigating {
                    HStack {
                        SpeedDisc(speedMps: model.speedMps, limitKmh: model.limitKmh)
                        Spacer()
                    }
                    .padding(.leading, 14)
                }
            }
            .padding(.bottom, isNavigating ? 110 : bottomCardHeight + 12)
            GeometryReader { geo in
                VStack {
                    Spacer()
                    bottomCard(available: geo.size.height)
                }
            }
        }
        .overlay(alignment: .top) {
            // Arrived: the trip's card is gone, the capsule says so.
            if model.arrived || DriveNoteSlot.forced == .arrive && isNavigating {
                DriveNoteSlot(arrival: true).padding(.horizontal, 14).padding(.top, 6)
            }
        }
        .onChange(of: roomTarget) { room.go(to: $0) }
        .onAppear { room.go(to: roomTarget) }
        .onAppear { model.isDark = colorScheme == .dark }
        .onChange(of: colorScheme) { s in model.isDark = s == .dark }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .fullScreenCover(isPresented: Binding(get: { moreScreen != nil }, set: { if !$0 { moreScreen = nil } })) {
            MorePagesLauncher(screen: moreScreen ?? "offline")
        }
        .sheet(isPresented: $model.showWatches) { WatchesView() }
        .sheet(isPresented: $showLayers) { MapLayersSheet() }
        .sheet(isPresented: $showTools) { ToolsSheet().presentationDetents([.medium, .large]) }
        .overlay {
            if showReport, let c = model.reportCoordinate {
                ReportFlow(coordinate: c, isPresented: $showReport).transition(.opacity)
            }
        }
        .animation(DG.springSoft, value: showReport)
        .overlay {
            if showWelcome, !model.prefs.welcomeDone || ProcessInfo.processInfo.arguments.contains("-csWelcome") {
                WelcomeOverlay { withAnimation(DG.springSoft) { showWelcome = false } }
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if let t = model.toast {
                Text(t).font(DG.font(15, .semibold)).foregroundStyle(DG.ink)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .dgGlass(Capsule()).padding(.top, 64).padding(.horizontal, 16)
                    .task(id: t) { try? await Task.sleep(nanoseconds: 2_500_000_000); if model.toast == t { model.toast = nil } }
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var isNavigating: Bool { model.state.isNavigating }

    private var roomTarget: CGFloat {
        CameraRoom.target(navigating: isNavigating && !model.arrived,
                          alertShown: model.alerts.cleared != nil || model.alerts.banner(within: model.prefs.stripAheadMeters) != nil,
                          opened: model.alertMore && model.alerts.cleared == nil)
    }

    private var showsEvent: Bool { model.selectedMarker != nil || model.alertFocus != nil }

    /// A watch alert whose event is over, with nothing else reported at
    /// the spot: it gets the cleared view.
    private var clearedWatch: (focus: AlertFocus, text: WatchClearedText)? {
        guard let f = model.alertFocus, model.selectedMarker == nil, f.nearby == nil,
              case let .cleared(at) = f.status else { return nil }
        return (f, WatchClearedText.make(f.ref, clearedAt: at))
    }

    /// How tall the bottom card is, so the map buttons sit above it. The
    /// event panel measures itself; pulled up past this it covers them.
    private var bottomCardHeight: CGFloat {
        if showsEvent { return min(panelHeight, 380) }
        switch model.state {
        case .browsing: return model.resumable == nil ? PlacesTray.height(rows: PlacesTray.rows(model.places).count) : 140
        case .found: return max(panelHeight - 20, 200)
        case .routing: return 80
        case .choosing: return max(panelHeight - 20, 240)
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
        if let c = model.alerts.cleared {
            DriveAlert(item: c, along: model.alerts.hereAlong, more: .constant(false), cleared: true, standalone: true)
        } else if let next = model.alerts.banner(within: model.prefs.stripAheadMeters) {
            DriveAlert(item: next, along: model.alerts.hereAlong, more: $browseAlertMore, standalone: true)
                .animation(DG.spring, value: next.id)
        }
    }

    @ViewBuilder private func bottomCard(available: CGFloat) -> some View {
        if let c = clearedWatch, !isNavigating {
            WatchClearedPanel(focus: c.focus, text: c.text)
                .background(GeometryReader { g in Color.clear.preference(key: PanelHeight.self, value: g.size.height) })
                .onPreferenceChange(PanelHeight.self) { panelHeight = $0 }
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if showsEvent, !isNavigating {
            EventPanel(available: available)
                .background(GeometryReader { g in Color.clear.preference(key: PanelHeight.self, value: g.size.height) })
                .onPreferenceChange(PanelHeight.self) { panelHeight = $0 }
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            switch model.state {
            case .browsing:
                if let trip = model.resumable { ResumeCard(trip: trip) } else {
                    // The keyboard covers the tray rather than lifting it.
                    PlacesTray().ignoresSafeArea(.keyboard)
                }
            case let .found(place):
                PlaceCard(place: place)
                    .background(GeometryReader { g in Color.clear.preference(key: PanelHeight.self, value: g.size.height) })
                    .onPreferenceChange(PanelHeight.self) { panelHeight = $0 }
                    .transition(.move(edge: .bottom))
            case .routing:
                HStack(spacing: 10) {
                    ProgressView(); Text("Finding routes")
                    Spacer()
                    Button("Cancel") { model.cancelRouting() }
                }
                    .font(DG.font(16, .semibold)).foregroundStyle(DG.ink)
                    .padding(.horizontal, 18).frame(height: 60).frame(maxWidth: .infinity)
                    .dgGlass(radius: DG.R.card)
                    .padding(12)
            case let .choosing(routes, place):
                RoutesCard(routes: routes, place: place)
                    .background(GeometryReader { g in Color.clear.preference(key: PanelHeight.self, value: g.size.height) })
                    .onPreferenceChange(PanelHeight.self) { panelHeight = $0 }
                    .transition(.move(edge: .bottom))
            case let .navigating(place):
                if case .complete = model.coreState?.tripState {
                    ArriveCard(place: place).transition(.move(edge: .bottom))
                }
            }
        }
    }
}

/// No signal: what still works, and how old the road reports are.
struct OfflineBanner: View {
    let title: String
    let detail: String

    var body: some View {
        DGNote(systemImage: DGIcon.offline, tone: .mid, title: title, detail: detail, identifier: "offline-banner")
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

private struct PanelHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
