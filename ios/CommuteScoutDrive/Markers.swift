import Combine
import CoreLocation
import MapLibre
import SwiftUI
import UIKit

/// The road markers the website draws, for the area on screen. Loaded
/// when the view settles, kept fresh every minute, filtered by the
/// Layers sheet. Nothing is fetched while zoomed out past a state.
@MainActor
final class MarkerStore: ObservableObject {
    @Published private(set) var markers: [RoadMarker] = []
    @Published private(set) var loading = false
    private var byKey: [String: RoadMarker] = [:]
    private var box: (s: Double, w: Double, n: Double, e: Double)?
    private var kinds = ""
    private var fetchedAt = Date.distantPast
    private var task: Task<Void, Never>?
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(force: true) }
        }
    }

    func marker(for key: String) -> RoadMarker? { byKey[key] }

    /// The visible area changed. Fetch when it moved outside the last box
    /// or the layer set changed; the box carries a margin so small pans
    /// do not hit the server.
    func view(bounds: MLNCoordinateBounds, zoom: Double, kinds: String) {
        guard zoom >= 5.5, !kinds.isEmpty else {
            if kinds.isEmpty { markers = []; byKey = [:] }
            return
        }
        let latPad = (bounds.ne.latitude - bounds.sw.latitude) * 0.5
        let lonPad = (bounds.ne.longitude - bounds.sw.longitude) * 0.5
        let inside = box.map { b in
            bounds.sw.latitude >= b.s && bounds.sw.longitude >= b.w && bounds.ne.latitude <= b.n && bounds.ne.longitude <= b.e
        } ?? false
        if inside && kinds == self.kinds && Date().timeIntervalSince(fetchedAt) < 60 { return }
        box = (bounds.sw.latitude - latPad, bounds.sw.longitude - lonPad, bounds.ne.latitude + latPad, bounds.ne.longitude + lonPad)
        self.kinds = kinds
        refresh(force: false)
    }

    func refresh(force: Bool) {
        guard let b = box, !kinds.isEmpty else { return }
        task?.cancel()
        task = Task { [kinds] in
            if !force { try? await Task.sleep(nanoseconds: 350_000_000) }   // let the pan settle
            guard !Task.isCancelled else { return }
            loading = true
            defer { loading = false }
            let result = await Task { try await LiveData.markers(in: (b.s, b.w, b.n, b.e), kinds: kinds) }.result
            if case let .failure(e) = result { NSLog("CS markers fetch failed: %@", String(describing: e)) }
            if case let .success(found) = result, !Task.isCancelled {
                NSLog("CS markers: %d in box", found.count)
                markers = found
                byKey = Dictionary(found.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
                fetchedAt = Date()
            }
        }
    }
}

/// One icon per marker kind, drawn once: a colored disc with a white glyph.
enum MarkerIcons {
    static let color: [String: UIColor] = [
        "incident": UIColor(red: 0.95, green: 0.62, blue: 0.10, alpha: 1),
        "lane_closure": UIColor(red: 0.84, green: 0.19, blue: 0.19, alpha: 1),
        "chain_control": UIColor(red: 0.16, green: 0.45, blue: 0.85, alpha: 1),
        "wildfire": UIColor(red: 0.90, green: 0.35, blue: 0.10, alpha: 1),
        "plugin": UIColor(red: 0.45, green: 0.30, blue: 0.80, alpha: 1),
    ]
    static let symbol: [String: String] = [
        "incident": "exclamationmark.triangle.fill",
        "lane_closure": "xmark.octagon.fill",
        "chain_control": "snowflake",
        "wildfire": "flame.fill",
        "plugin": "person.2.fill",
    ]
    static let kinds = ["incident", "lane_closure", "chain_control", "wildfire", "plugin"]

    static func tint(_ kind: String) -> Color { Color(color[kind] ?? .gray) }
    static func name(_ kind: String) -> String { symbol[kind] ?? "mappin.circle.fill" }

    static let images: [String: UIImage] = {
        var out: [String: UIImage] = [:]
        for k in kinds {
            let size = CGSize(width: 30, height: 30)
            let img = UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor.white.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
                (color[k] ?? .gray).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 2.5, dy: 2.5))
                let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
                if let glyph = UIImage(systemName: symbol[k] ?? "mappin", withConfiguration: config)?
                    .withTintColor(.white, renderingMode: .alwaysOriginal) {
                    let r = CGRect(x: (size.width - glyph.size.width) / 2, y: (size.height - glyph.size.height) / 2,
                                   width: glyph.size.width, height: glyph.size.height)
                    glyph.draw(in: r)
                }
            }
            out[k] = img
        }
        return out
    }()
}

/// What a tapped marker says: the website's popup, on the phone.
struct MarkerCard: View {
    @EnvironmentObject var model: AppModel
    let marker: RoadMarker

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: MarkerIcons.name(marker.kind)).font(.title2).foregroundStyle(MarkerIcons.tint(marker.kind))
                VStack(alignment: .leading, spacing: 2) {
                    Text(marker.displayTitle).font(.headline).lineLimit(3)
                    ForEach(marker.detailLines, id: \.self) { line in
                        Text(line).font(.caption).foregroundStyle(.secondary)
                    }
                    if let here = model.here {
                        Text(Units.distance(AlertsEngine.meters(here, marker.coordinate)) + " from you")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { model.clearMarker() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
            HStack(spacing: 8) {
                Button {
                    model.show(Place(name: marker.displayTitle, coordinate: marker.coordinate, kind: .recent))
                } label: {
                    Label("Navigate here", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                ShareLink(item: marker.webURL) {
                    Image(systemName: "square.and.arrow.up").padding(.vertical, 10).padding(.horizontal, 14)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(12)
    }
}
