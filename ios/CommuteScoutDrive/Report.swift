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

/// The Waze-style report sheet: one tap on a kind, an optional note, send.
/// The location is where the driver is (or the pin, when browsing one).
struct ReportSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let coordinate: CLLocationCoordinate2D
    @State private var kind: String?
    @State private var note = ""
    @State private var error: String?
    @State private var showSignIn = false

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !model.account.signedIn {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.exclamationmark").foregroundStyle(.orange)
                            Text("Reports need an account, the same one as the website.").font(.footnote)
                            Spacer()
                            Button("Sign in") { showSignIn = true }.buttonStyle(.bordered).controlSize(.small)
                        }
                        .padding(12).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(ReportKinds.all, id: \.kind) { k in
                            Button { kind = k.kind } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: k.symbol).font(.title2)
                                    Text(k.label).font(.caption).multilineTextAlignment(.center).lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, minHeight: 74)
                                .padding(8)
                                .background(kind == k.kind ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground),
                                            in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(kind == k.kind ? Color.accentColor : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("report-\(k.kind)")
                        }
                    }
                    TextField("Add a note (optional)", text: $note, axis: .vertical).lineLimit(1 ... 3)
                        .textFieldStyle(.roundedBorder)
                    Text("Reported at \(coordinate.pretty). Reports show on the map for everyone and go to the plugins you use, under a pseudonym.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button {
                        Task { await send() }
                    } label: {
                        Label(model.reporter.sending ? "Sending" : "Send report", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(kind == nil || model.reporter.sending)
                    .accessibilityIdentifier("report-send")
                }
                .padding(16)
            }
            .navigationTitle("Report")
            .toolbar { Button("Cancel") { dismiss() } }
            .sheet(isPresented: $showSignIn) { SignInSheet(reason: "Sign in to send reports.") }
            .alert("Could not send", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func send() async {
        guard let kind else { return }
        guard let token = await model.account.token() else { showSignIn = true; return }
        do {
            try await model.reporter.send(kind: kind, at: coordinate, heading: model.courseDegrees, description: note, token: token)
            model.markers.refresh(force: true)
            model.toast = "Thanks. Your report is on the map."
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
