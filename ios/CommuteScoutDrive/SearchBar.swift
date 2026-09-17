import CoreLocation
import SwiftUI

/// Find anything: an address, a place, or coordinates typed as
/// "37.35, -121.94". Always on screen while browsing; a result becomes
/// a pin with Navigate and Save, the same as the website.
struct SearchBar: View {
    @EnvironmentObject var model: AppModel
    @State private var text = ""
    @State private var results: [Suggestion] = []
    @State private var searching = false
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search a place, address or coordinates", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { Task { await submit() } }
                    .onChange(of: text) { new in schedule(new) }
                if !text.isEmpty {
                    Button { text = ""; results = [] } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)

            if focused, text.isEmpty {
                shortcuts
            } else if !results.isEmpty, focused {
                resultList
            }
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.places.recents.prefix(5)) { p in row(systemImage: "clock", title: p.shortName, sub: p.name) { pick(p) } }
            if let home = model.places.home { row(systemImage: "house", title: "Home", sub: home.shortName) { pick(home) } }
            if let work = model.places.work { row(systemImage: "briefcase", title: "Work", sub: work.shortName) { pick(work) } }
            ForEach(model.places.saved.prefix(6)) { p in row(systemImage: "star", title: p.shortName, sub: p.name) { pick(p) } }
            if model.places.places.isEmpty {
                Text("Type a place, an address, or coordinates like 37.35, -121.94.")
                    .font(.footnote).foregroundStyle(.secondary).padding(12)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.top, 6)
    }

    private var resultList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(results) { s in
                row(systemImage: "mappin", title: s.name.split(separator: ",").first.map(String.init) ?? s.name,
                    sub: s.name) { pick(Place(name: s.name, coordinate: s.coordinate, kind: .recent)) }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.top, 6)
    }

    private func row(systemImage: String, title: String, sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage).frame(width: 20).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body).foregroundStyle(.primary).lineLimit(1)
                    if sub != title { Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    private func pick(_ place: Place) {
        focused = false
        text = ""
        results = []
        model.show(place)
    }

    private func schedule(_ q: String) {
        task?.cancel()
        results = []
        if let coord = Self.parseCoordinates(q) {
            results = [Suggestion(name: coord.pretty, lat: coord.latitude, lon: coord.longitude)]
            return
        }
        guard q.count >= 2 else { return }
        task = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            if let found = try? await Search.suggest(q, near: model.here), !Task.isCancelled {
                results = found
            }
        }
    }

    private func submit() async {
        if let coord = Self.parseCoordinates(text) {
            pick(Place(name: coord.pretty, coordinate: coord, kind: .recent))
            return
        }
        if let first = results.first {
            pick(Place(name: first.name, coordinate: first.coordinate, kind: .recent))
            return
        }
        searching = true
        defer { searching = false }
        if let found = try? await Search.geocode(text), let first = found.first {
            pick(Place(name: first.name, coordinate: first.coordinate, kind: .recent))
        } else {
            model.errorMessage = "Nothing found for \"\(text)\"."
        }
    }

    /// "37.35, -121.94", "37.35 -121.94", "37.35,-121.94", or with N/W letters.
    static func parseCoordinates(_ s: String) -> CLLocationCoordinate2D? {
        let cleaned = s.uppercased().replacingOccurrences(of: "°", with: " ")
        let pattern = #"^\s*(-?\d{1,2}(?:\.\d+)?)\s*([NS])?\s*[,\s]\s*(-?\d{1,3}(?:\.\d+)?)\s*([EW])?\s*$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) else { return nil }
        func group(_ i: Int) -> String? {
            guard let r = Range(m.range(at: i), in: cleaned) else { return nil }
            return String(cleaned[r])
        }
        guard var lat = Double(group(1) ?? ""), var lon = Double(group(3) ?? "") else { return nil }
        if group(2) == "S" { lat = -abs(lat) }
        if group(4) == "W" { lon = -abs(lon) }
        guard (-90 ... 90).contains(lat), (-180 ... 180).contains(lon) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
