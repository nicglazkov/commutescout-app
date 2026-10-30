import CoreLocation
import SwiftUI

/// What a driver can report, the website's list, in the order people
/// reach for them. Kinds are the Flare vocabulary.
enum ReportKinds {
    static let all: [(kind: String, label: String, symbol: String)] = [
        ("POLICE_VISIBLE", "Police", "shield.lefthalf.filled"),
        ("CRASH_MAJOR", "Crash", "car.side.rear.and.collision.and.car.side.front"),
        ("HAZARD_ON_ROAD", "Hazard on road", "exclamationmark.triangle.fill"),
        ("HAZARD_SHOULDER_CAR", "Car on shoulder", "car.side"),
        ("ROAD_CLOSED", "Road closed", "xmark.octagon.fill"),
        ("LANE_CLOSED", "Lane closed", "road.lanes"),
        ("JAM_HEAVY", "Traffic jam", "car.2.fill"),
        ("WEATHER_FOG", "Fog or weather", "cloud.fog.fill"),
        ("WEATHER_FLOOD", "Flooding", "water.waves"),
        ("WEATHER_ICE", "Ice or snow", "snowflake"),
        ("CHAINS_REQUIRED", "Chains required", "link"),
        ("CHAINS_NOT_REQUIRED", "Chains not needed", "link.badge.plus"),
        ("CAMERA_ISSUE", "Camera issue", "camera.fill"),
        ("MAP_ISSUE", "Map issue", "map.fill"),
    ]
}

/// Sends a report to commutescout.com, which fans it out to plugins.
@MainActor
final class Reporter: ObservableObject {
    @Published var sending = false
    @Published var lastSent: String?

    func send(kind: String, at coordinate: CLLocationCoordinate2D, heading: Double?, description: String,
              token: String) async throws {
        sending = true
        defer { sending = false }
        var body: [String: Any] = ["kind": kind, "lat": coordinate.latitude, "lon": coordinate.longitude,
                                   "client": "commutescout-ios/\(AppInfo.version)"]
        if let heading, heading >= 0 { body["heading_deg"] = heading }
        if !description.isEmpty { body["description"] = description }
        let (status, data) = try await Backend.send("POST", "api/flare/report", token: token, body: body)
        guard status == 201 || status == 202 else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"]
            throw ReportError.refused(status, (msg as? String) ?? (msg as? [String: Any])?["message"] as? String ?? "The server refused the report.")
        }
        lastSent = kind
    }

    func confirm(alertId: String, vote: String, token: String) async throws {
        let (status, _) = try await Backend.send("POST", "api/flare/confirm", token: token,
                                                 body: ["alert_id": alertId, "vote": vote])
        guard status == 200 else { throw ReportError.refused(status, "Could not record that.") }
    }
}

enum ReportError: LocalizedError {
    case refused(Int, String)
    var errorDescription: String? {
        switch self {
        case let .refused(code, msg): code == 429 ? "Too many reports for now. Try again in a minute." : msg
        }
    }
}

/// The twelve kinds on the report grid, in the mockup's order, with the
/// Flare kind each one sends and whether it asks which lane.
extension ReportGrid {
    struct Item: Hashable {
        let kind: String
        let label: String
        let symbol: String
        let tone: DGTone
        let dg: DGKind
        let asksLane: Bool
        /// "a crash", for "Report a crash here".
        let phrase: String
    }

    static let items: [Item] = [
        Item(kind: "CRASH_MAJOR", label: "Crash", symbol: "car.fill", tone: .high, dg: .crash, asksLane: true, phrase: "a crash"),
        Item(kind: "JAM_HEAVY", label: "Slowdown", symbol: "car.2.fill", tone: .mid, dg: .jam, asksLane: false, phrase: "a slowdown"),
        Item(kind: "POLICE_VISIBLE", label: "Police", symbol: "shield.lefthalf.filled", tone: .low, dg: .police, asksLane: false, phrase: "police"),
        Item(kind: "HAZARD_ON_ROAD", label: "Object on road", symbol: "exclamationmark.triangle.fill", tone: .mid, dg: .hazard, asksLane: true, phrase: "an object on the road"),
        Item(kind: "HAZARD_SHOULDER_CAR", label: "Car on shoulder", symbol: "car.side.fill", tone: .mid, dg: .hazard, asksLane: true, phrase: "a car on the shoulder"),
        Item(kind: "ROAD_CLOSED", label: "Road closed", symbol: "xmark.octagon.fill", tone: .high, dg: .closure, asksLane: false, phrase: "a road closure"),
        Item(kind: "LANE_CLOSED", label: "Lane closed", symbol: "road.lanes", tone: .high, dg: .closure, asksLane: true, phrase: "a lane closure"),
        Item(kind: "WEATHER_ICE", label: "Ice or snow", symbol: "snowflake", tone: .mid, dg: .ice, asksLane: false, phrase: "ice or snow"),
        Item(kind: "WEATHER_FOG", label: "Fog", symbol: "cloud.fog.fill", tone: .mid, dg: .hazard, asksLane: false, phrase: "fog"),
        Item(kind: "WEATHER_FLOOD", label: "Flooding", symbol: "water.waves", tone: .high, dg: .hazard, asksLane: false, phrase: "flooding"),
        Item(kind: "CHAINS_REQUIRED", label: "Chains required", symbol: "link", tone: .high, dg: .chain, asksLane: false, phrase: "chains required"),
        Item(kind: "MAP_ISSUE", label: "Map issue", symbol: "map.fill", tone: .low, dg: .sign, asksLane: false, phrase: "a map issue"),
    ]
}

/// Report, like Waze but calmer: pick a kind on a grid, check it on a
/// card with the lane picked, and it sends on its own after 5 seconds
/// unless Undo. The spot is where the driver is (or the pin, browsing
/// one), snapped to the nearest road within 60 m.
struct ReportFlow: View {
    @EnvironmentObject var model: AppModel
    let coordinate: CLLocationCoordinate2D
    @Binding var isPresented: Bool

    private enum Step: Equatable { case grid, confirm(ReportGrid.Item), sent }
    @State private var step: Step = .grid
    @State private var note = ""
    @State private var lane: ReportGrid.Lane = .right
    @State private var error: String?
    @State private var showSignIn = false
    @State private var snapped: Snap?
    @State private var useExact = false
    @State private var countdown: Task<Void, Never>?
    @State private var fill: CGFloat = 0
    @FocusState private var noteFocused: Bool

    struct Snap: Decodable {
        let snapped: Bool
        let lat: Double
        let lon: Double
        let road: String?
        let distance_m: Double
    }

    private var placed: CLLocationCoordinate2D {
        if let s = snapped, s.snapped, !useExact { return CLLocationCoordinate2D(latitude: s.lat, longitude: s.lon) }
        return coordinate
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.18).ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityHidden(true)
            TripSheet(identifier: "report-sheet") {
                Group {
                    switch step {
                    case .grid: grid
                    case let .confirm(item): confirm(item)
                    case .sent: sent
                    }
                }
                .padding(.horizontal, 16)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            .transition(.move(edge: .bottom))
        }
        .animation(DG.springSoft, value: step)
        .task {
            snapped = try? await Backend.get("api/snap", query: ["lat": String(format: "%.6f", coordinate.latitude),
                                                                "lon": String(format: "%.6f", coordinate.longitude)], as: Snap.self)
        }
        .sheet(isPresented: $showSignIn) { SignInSheet(reason: "Sign in to send reports.") }
        .alert("Could not send", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    // MARK: grid

    private var grid: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Report").font(DG.T.sheetTitle).foregroundStyle(DG.ink)
                    Text(roadLine).font(DG.font(14)).foregroundStyle(DG.sub).lineLimit(1)
                }
                Spacer()
                DGBackButton(symbol: "xmark") { close() }.accessibilityIdentifier("report-close")
            }
            if !model.account.signedIn {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark").foregroundStyle(DGTone.mid.ink)
                    Text("Reports need an account, the same one as the website.").font(DG.font(13.5, .medium)).foregroundStyle(DG.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Sign in") { showSignIn = true }.font(DG.font(14, .semibold)).foregroundStyle(DGTone.low.ink)
                }
                .padding(12).dgTintBox(.mid, radius: 16).padding(.top, 12)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(ReportGrid.items, id: \.kind) { k in
                    Button { pick(k) } label: {
                        VStack(spacing: 7) {
                            DGDisc(systemImage: k.symbol, tone: k.tone, size: 36)
                            Text(k.label).font(DG.font(13, .semibold)).foregroundStyle(DG.ink)
                                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity).frame(height: 84)
                        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(DG.hair, lineWidth: 1))
                    }
                    .buttonStyle(DGPressStyle())
                    .accessibilityIdentifier("report-\(k.kind)")
                }
            }
            .padding(.top, 14)
            Text("Placed on the road where you are now. Shown to everyone under a pseudonym.")
                .font(DG.font(12.5)).foregroundStyle(DG.sub).padding(.top, 12).padding(.bottom, 6)
        }
    }

    private var roadLine: String {
        if let s = snapped, s.snapped, let r = s.road, !r.isEmpty {
            return [r, ReportGrid.bound(model.courseDegrees)].compactMap { $0 }.joined(separator: ", ")
        }
        return placed.pretty
    }

    // MARK: confirm

    private func confirm(_ k: ReportGrid.Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                DGDisc(systemImage: k.symbol, tone: k.tone, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Report \(k.phrase) here" + (ReportGrid.bound(model.courseDegrees).map { ", \($0)" } ?? ""))
                        .font(DG.font(20, .bold)).foregroundStyle(DG.ink).fixedSize(horizontal: false, vertical: true)
                    Text(roadLine).font(DG.font(14)).foregroundStyle(DG.sub).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if k.asksLane {
                LaneDrawing(kind: k.dg, layout: ReportGrid.layout(lane), size: .large)
                    .frame(height: 108).frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: DG.R.box, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: DG.R.box, style: .continuous))
                    .padding(.top, 14)
                    .animation(DG.snap, value: lane)
                DGSegmented(options: ReportGrid.Lane.allCases.map { ($0, $0.rawValue, nil) },
                            selection: Binding(get: { lane }, set: { lane = $0; restart() }), identifier: "report-lane")
                    .padding(.top, 10)
            }
            if let s = snapped, s.snapped {
                HStack(spacing: 6) {
                    Image(systemName: "road.lanes").foregroundStyle(DG.sub)
                    Text(useExact ? "At the exact spot." : "On \(s.road ?? "the road").").font(DG.font(13)).foregroundStyle(DG.sub)
                    Spacer()
                    Button(useExact ? "Snap to road" : "Use the exact spot") { useExact.toggle(); restart() }
                        .font(DG.font(13, .semibold)).foregroundStyle(DGTone.low.ink).accessibilityIdentifier("report-exact")
                }
                .padding(.top, 10)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("report-snap")
            }
            TextField("Add a note (optional)", text: $note, axis: .vertical).lineLimit(1 ... 3)
                .font(DG.font(15)).focused($noteFocused)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(DG.hair, lineWidth: 1))
                .padding(.top, 12)
                .onChange(of: noteFocused) { f in if f { stopCountdown() } else { restart() } }
            Text(countdown == nil ? "Tap Send now when you are ready." : "Sends on its own in 5 s, or tap Undo.")
                .font(DG.font(12.5)).foregroundStyle(DG.sub).padding(.top, 10)
            HStack(spacing: 10) {
                Button { undo() } label: { Text("Undo").frame(maxWidth: .infinity) }
                    .buttonStyle(.dgGlass)
                    .accessibilityIdentifier("report-undo")
                Button { Task { await send(k) } } label: {
                    Text(model.reporter.sending ? "Sending" : "Send now").frame(maxWidth: .infinity)
                }
                .buttonStyle(.dgPrimary)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        Capsule().fill(Color.white.opacity(0.18)).frame(width: g.size.width * fill)
                    }
                    .allowsHitTesting(false)
                    .clipShape(Capsule())
                }
                .disabled(model.reporter.sending)
                .accessibilityIdentifier("report-send")
            }
            .padding(.top, 12).padding(.bottom, 4)
        }
    }

    // MARK: sent

    private var sent: some View {
        VStack(spacing: 0) {
            DGDisc(systemImage: "checkmark", tone: .good, size: 56).padding(.top, 8)
            Text("Thanks, it's on the map").font(DG.T.sheetTitle).foregroundStyle(DG.ink).padding(.top, 14)
            Text("Drivers coming up behind you can confirm it or say it's gone. It leaves the map once it's cleared.")
                .font(DG.font(15)).foregroundStyle(DG.sub).multilineTextAlignment(.center).padding(.top, 6).padding(.horizontal, 8)
            Button { close() } label: { Text("Done").frame(maxWidth: .infinity) }
                .buttonStyle(.dgPrimary).padding(.top, 18).padding(.bottom, 4)
                .accessibilityIdentifier("report-done")
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: flow

    private func pick(_ k: ReportGrid.Item) {
        // A report needs an account; without one the grid says so and
        // the tap asks to sign in, unless there is no signal to sign in
        // with (the report then waits in the queue).
        if !model.account.signedIn, model.online, !Self.preview { showSignIn = true; return }
        lane = k.kind == "HAZARD_SHOULDER_CAR" ? .shoulder : .right
        step = .confirm(k)
        restart()
    }

    private func restart() {
        guard case let .confirm(k) = step, !noteFocused, !Self.preview else { return }
        stopCountdown()
        fill = 0
        withAnimation(.linear(duration: 5)) { fill = 1 }
        countdown = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await send(k)
        }
    }

    /// UI tests: the confirm card without an account and without the
    /// countdown, so nothing is ever sent from a test.
    static let preview = ProcessInfo.processInfo.arguments.contains("-csReportPreview")

    private func stopCountdown() {
        countdown?.cancel()
        countdown = nil
        withAnimation(.easeOut(duration: 0.2)) { fill = 0 }
    }

    private func undo() {
        stopCountdown()
        note = ""
        step = .grid
    }

    private func close() {
        stopCountdown()
        isPresented = false
    }

    private func send(_ k: ReportGrid.Item) async {
        stopCountdown()
        if Self.preview { showSignIn = true; return }
        let text = ReportGrid.description(note: note, lane: k.asksLane ? lane : nil)
        // No signal: keep it and send it when there is one. A signed-in
        // driver's token cannot be refreshed offline, and asking them to
        // sign in again would be the wrong answer to a dead zone.
        if !model.online, model.account.signedIn {
            queue(k.kind, text)
            return
        }
        guard let token = await model.account.token() else {
            if !model.online { error = OfflineText.retry } else { showSignIn = true }
            return
        }
        do {
            try await model.reporter.send(kind: k.kind, at: placed, heading: model.courseDegrees, description: text, token: token)
            model.markers.refresh(force: true)
            step = .sent
        } catch {
            if Connectivity.isOffline(error) { queue(k.kind, text) } else { self.error = error.localizedDescription }
        }
    }

    private func queue(_ kind: String, _ text: String) {
        PendingReport.add(PendingReport(kind: kind, lat: placed.latitude, lon: placed.longitude,
                                        heading: model.courseDegrees, note: text, createdAt: Date()))
        DriveLog.note("report \(kind) queued: no connection")
        model.toast = "No connection. Your report sends when you are back online, if within 15 minutes."
        close()
    }
}
