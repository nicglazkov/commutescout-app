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
    // "-csOpenMore market|plugin|offline|picker|savedmap|watches" opens that page at launch (debug builds).
    @State private var moreScreen: String? = OfflineLaunch.wanted
    @State private var showLayers = false
    @State private var showReport = false
    @State private var navSheet: NavSheet?
    @State private var endingTrip = false
    @State private var showTools = false
    @State private var searchActive = false
    /// The event panel's height as laid out, so the map buttons sit above it.
    @State private var panelHeight: CGFloat = 0
    @State private var browseAlertMore = false
    /// The room the map makes under a tucked alert, eased in and out.
    @StateObject private var room = CameraRoomAnimator()

    var body: some View {
        let _ = PerfProbe.count("body")
        ZStack(alignment: .top) {
            // The navigation view owns the safe area: the maneuver card
            // and the trip bar clear the island and the home indicator.
            DynamicallyOrientingNavigationView(
                styleURL: model.styleURL,
                camera: $model.camera,
                navigationCamera: model.navigationCamera,
                navigationState: model.coreState,
                // The app's own fixes for the dot: no second GPS client in the map.
                locationManagerConfiguration: NavigationLocationManagerConfiguration(
                    nonNavigatingLocationManager: model.mapFeed, navigatingLocationManager: model.navPuck),
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
            // The ahead line owns the left side on a trip, so the speed
            // disc sits on the right; everything else is in the trip bar.
            .navigationViewInnerGrid(topCenter: { EmptyView() }, bottomTrailing: {
                if isNavigating, model.prefs.showSpeedLimit, model.tripChange == nil {
                    SpeedDisc(speedMps: model.speedMps, limitKmh: model.limitKmh)
                }
            })
            // Day Glass+: the maneuver card with the alert tucked under
            // it, the trip bar, and no road-name pill (the card says it).
            .navigationViewInstructionView { state, _, size in DriveTop(state: state, size: size) }
            .navigationViewProgressView { state, exit in
                if endingTrip, model.tripChange == nil {
                    EndTripBar(destination: tripDestination?.shortName ?? "your destination",
                               onKeep: { endingTrip = false }, onEnd: { endingTrip = false; exit?() })
                } else if let c = model.tripChange {
                    TripChangeBar(seconds: c.seconds, cost: TripPlan.cost(c.addedSeconds),
                                  line: TripPlan.line(stops: c.stops.map(\.shortName), destination: c.destination.shortName),
                                  confirm: c.added != nil ? "Add stop" : "Go here",
                                  onCancel: { model.cancelTripChange() }, onConfirm: { model.applyTripChange() })
                } else {
                    TripBar(state: state, onExit: { model.alertMore = false; endingTrip = true }, onAddStop: { model.alertMore = false; navSheet = .stop },
                            onRoute: { model.alertMore = false; navSheet = .trip })
                }
            }
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
                    // The compass shows only off a trip; small turns are not
                    // worth redrawing the whole screen for.
                    if !isNavigating, PowerPolicy.headingWorthShowing(old: model.heading, new: heading) {
                        model.heading = heading
                    }
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
                        SearchBar(active: $searchActive)
                        if !searchActive {
                            VStack(spacing: 10) {
                                DGRoundButton(size: 52) { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                                    .accessibilityLabel("Settings")
                                    .accessibilityIdentifier("settings")
                                DGRoundButton(size: 52) { showTools = true } label: { Image(systemName: "square.grid.2x2.fill") }
                                    .accessibilityLabel("Tools")
                                    .accessibilityIdentifier("tools")
                                DGModesPill(is3D: model.prefs.is3D) { withAnimation(DG.tilt) { model.toggle3D() } }
                            }
                            .transition(.opacity)
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
                    .opacity(searchActive ? 0 : 1)
                    .allowsHitTesting(!searchActive)
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
            // The ahead line, down the left between the card and the trip bar.
            if isNavigating, !model.arrived, model.tripChange == nil, !model.alertMore, !showReport,
               let p = model.coreState?.currentProgress {
                GeometryReader { geo in
                    VStack {
                        Spacer()
                        HStack {
                            AheadRail(marks: railMarks, destination: tripDestination?.shortName ?? "Destination",
                                      toDestination: Units.distance(p.distanceRemaining), totalMeters: p.distanceRemaining,
                                      stops: model.tripStops.count) { m in
                                if let u = model.alerts.ahead.first(where: { $0.id == m.id }) {
                                    model.alerts.say(u.marker)
                                    model.showMarker(key: u.marker.key)
                                }
                            }
                            .frame(width: 220, height: min(360, max(200, geo.size.height * 0.40)), alignment: .leading)
                            Spacer()
                        }
                        .padding(.leading, 14)
                    }
                    .padding(.bottom, 166)
                    .opacity(geo.size.height >= 560 ? 1 : 0)
                }
                .transition(.opacity)
            }
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
        .sheet(item: $navSheet) { which in
            Group {
                switch which {
                case .stop:
                    PlacePickSheet(title: "Add a stop", sub: "On the way to \(tripDestination?.shortName ?? "your destination")", quick: true,
                                   exclude: (tripDestination.map { [$0] } ?? []) + model.tripStops,
                                   onPick: { model.previewStop($0) }, onClose: { navSheet = nil })
                case .destination:
                    PlacePickSheet(title: "Change destination", sub: "Your stops stay on the trip", quick: false,
                                   exclude: tripDestination.map { [$0] } ?? [],
                                   onPick: { model.previewDestination($0) }, onClose: { navSheet = nil })
                case .trip:
                    if let d = tripDestination {
                        YourTripSheet(destination: d,
                                  arrive: model.coreState?.currentProgress.map { Date().addingTimeInterval($0.durationRemaining).formatted(date: .omitted, time: .shortened) },
                                  onChangeDestination: { navSheet = .destination }, onAddStop: { navSheet = .stop },
                                  onReport: {
                                      // One sheet at a time: let this one leave before the report sheet comes up.
                                      navSheet = nil
                                      guard model.reportCoordinate != nil else { return }
                                      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showReport = true }
                                  },
                                  onClose: { navSheet = nil })
                    }
                }
            }
            .environmentObject(model)
            .presentationDetents([.fraction(0.64), .large])
            .presentationDragIndicator(.visible)
        }
        // A route on offer closes the sheet that asked for it: the map shows it.
        .onChange(of: model.tripChange) { if $0 != nil { navSheet = nil } }
        .onChange(of: isNavigating) { if !$0 { navSheet = nil; endingTrip = false } }
        .onChange(of: model.debugNavSheet) { if let n = $0.flatMap(NavSheet.init(rawValue:)) { navSheet = n; model.debugNavSheet = nil } }
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

    private var tripDestination: Place? { if case let .navigating(p) = model.state { return p }; return nil }

    /// What is ahead on the route, as marks for the ahead line.
    private var railMarks: [RailMark] {
        let along = model.alerts.hereAlong
        return model.alerts.ahead.filter { $0.alongMeters > along + 30 && !model.alerts.dismissed.contains($0.id) }.prefix(6).map { u in
            let k = DGKind(marker: u.marker)
            return RailMark(id: u.id, icon: DGIcon.name(k), tone: k.tone, distance: Units.distance(u.alongMeters - along),
                            title: k.short.replacingOccurrences(of: " ahead", with: ""), gapMeters: u.alongMeters - along)
        }
    }

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
            .font(DG.font(14, .bold))
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
                if let trip = model.resumable {
                    if !searchActive { ResumeCard(trip: trip) }
                } else {
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
                Text("Resume your trip to \(trip.place.shortName)?").font(DG.T.noteTitle).foregroundStyle(DG.ink)
                Text("Started at \(OfflineText.time(trip.startedAt)). Works without a signal.")
                    .font(DG.T.rowSub).foregroundStyle(DG.sub)
            }
            HStack(spacing: 8) {
                Button { model.resume() } label: {
                    Label("Resume", systemImage: "location.north.line.fill")
                }
                .buttonStyle(.dgBlue)
                .accessibilityIdentifier("resume-trip")
                Button("Not now") { model.dismissResume() }
                    .buttonStyle(.dgGlass)
                    .accessibilityIdentifier("dismiss-trip")
            }
        }
        .padding(16)
        .dgGlass(radius: DG.R.card)
        .padding(12)
    }
}

private struct PanelHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
