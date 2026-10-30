import CoreLocation
import SwiftUI

/// Find anything: an address, a place, or coordinates typed as
/// "37.35, -121.94". Always on screen while browsing; a result becomes
/// a pin with its place sheet, the same as the website.
///
/// Saved and recent places match instantly as you type. The server is
/// asked after a short pause; earlier answers stay on screen until a
/// newer one lands, and out-of-order replies are dropped.
struct SearchBar: View {
    @EnvironmentObject var model: AppModel
    /// True while typing: the map's own buttons step aside for the results.
    @Binding var active: Bool
    @State private var text = ""
    @State private var results: [Suggestion] = []
    @State private var searching = false
    @State private var seq = 0
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if focused {
                    Button { text = ""; results = []; focused = false } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(DG.ink)
                            .frame(width: 26, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("search-back")
                } else {
                    Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .semibold)).foregroundStyle(DG.sub)
                }
                TextField("Where to?", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { Task { await submit() } }
                    .onChange(of: text) { new in schedule(new) }
                    .accessibilityIdentifier("search")
                if searching { ProgressView().controlSize(.small) }
                if !text.isEmpty {
                    Button { text = ""; results = [] } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(DG.sub)
                            .frame(width: 26, height: 26).background(DG.ink.opacity(0.07), in: Circle())
                    }
                    .accessibilityLabel("Clear")
                    .accessibilityIdentifier("search-clear")
                }
            }
            .font(DG.font(17, .medium))
            .foregroundStyle(DG.ink)
            .padding(.leading, 20).padding(.trailing, 14).frame(height: 54)
            .dgGlass(radius: DG.R.cap)

            if focused, text.isEmpty {
                quickPills.padding(.top, 10)
                    .transition(.opacity.combined(with: .offset(y: -6)))
                if !shortcutList.isEmpty || (model.places.home == nil && model.places.work == nil) {
                    shortcuts.transition(.opacity.combined(with: .offset(y: -6)))
                }
            } else if focused, !text.isEmpty {
                resultList.transition(.opacity)
            }
        }
        .animation(DG.springSoft, value: focused)
        .animation(DG.springSoft, value: text.isEmpty)
        .onChange(of: focused) { new in withAnimation(DG.springSoft) { active = new } }
    }

    /// Saved and recent places whose name starts with what was typed.
    private var localMatches: [Place] {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 1 else { return [] }
        return model.places.places.filter { $0.name.lowercased().hasPrefix(q) || $0.shortName.lowercased().hasPrefix(q)
            || ($0.kind == .home && "home".hasPrefix(q)) || ($0.kind == .work && "work".hasPrefix(q)) }
            .prefix(3).map { $0 }
    }

    /// Home and Work as two big pills, one tap each.
    @ViewBuilder private var quickPills: some View {
        if model.places.home != nil || model.places.work != nil {
            HStack(spacing: 10) {
                if let home = model.places.home { pill("Home", "house.fill", home) }
                if let work = model.places.work { pill("Work", "briefcase.fill", work) }
            }
        }
    }

    private func pill(_ title: String, _ symbol: String, _ p: Place) -> some View {
        HStack(spacing: 0) {
            Button { pick(p) } label: {
                HStack(spacing: 10) {
                    Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(DG.path, in: Circle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).font(DG.font(15.5, .semibold)).foregroundStyle(DG.ink)
                        Text(away(p) ?? p.shortName).font(DG.font(12.5, .medium)).foregroundStyle(DG.sub).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12).frame(height: 58).contentShape(Rectangle())
            }
            .buttonStyle(DGPressStyle())
            .accessibilityIdentifier("quick-\(title.lowercased())")
            Button { model.places.remove(p) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(DG.faint)
                    .padding(10).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(title)")
            .accessibilityIdentifier("remove-place")
        }
        .frame(maxWidth: .infinity)
        .dgGlass(radius: 29)
    }

    private func away(_ p: Place) -> String? {
        guard let here = model.here else { return nil }
        return Units.distance(AlertsEngine.meters(here, p.coordinate))
    }

    /// Up to 5 favorites, then the last 10 destinations.
    private var shortcutList: [(Place, String)] {
        model.places.saved.prefix(5).map { ($0, "star.fill") } + model.places.recents.prefix(10).map { ($0, "clock.arrow.circlepath") }
    }

    /// Favorites and recents, any of them removable; Home and Work are
    /// the pills above.
    private var shortcuts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(shortcutList.enumerated()), id: \.element.0.id) { i, item in
                    if i > 0 { DGDivider(inset: 66) }
                    row(systemImage: item.1, ghost: item.0.kind == .recent, title: item.0.shortName, sub: item.0.name,
                        place: item.0, remove: { model.places.remove(item.0) }) { pick(item.0) }
                }
                if shortcutList.isEmpty { hint }
            }
        }
        .frame(maxHeight: 380)
        .fixedSize(horizontal: false, vertical: true)
        .dgGlass(radius: DG.R.card)
        .padding(.top, 10)
    }

    private var hint: some View {
        Text("Search a place, an address, or coordinates like 37.35, -121.94.")
            .font(DG.font(13.5)).foregroundStyle(DG.sub).padding(16)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var resultList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(localMatches.enumerated()), id: \.element.id) { i, p in
                if i > 0 { DGDivider(inset: 66) }
                row(systemImage: p.kind == .home ? "house.fill" : p.kind == .work ? "briefcase.fill" : p.kind == .saved ? "star.fill" : "clock.arrow.circlepath",
                    ghost: p.kind == .recent, title: p.kind == .home ? "Home" : p.kind == .work ? "Work" : p.shortName, sub: p.name, place: p) { pick(p) }
            }
            ForEach(Array(results.enumerated()), id: \.element.id) { i, s in
                if i > 0 || !localMatches.isEmpty { DGDivider(inset: 66) }
                let p = Place(name: s.name, coordinate: s.coordinate, kind: .recent)
                row(systemImage: "mappin", ghost: false, title: s.name.split(separator: ",").first.map(String.init) ?? s.name,
                    sub: s.name.split(separator: ",").dropFirst().joined(separator: ",").trimmingCharacters(in: .whitespaces),
                    place: p) { pick(p) }
            }
            if results.isEmpty, localMatches.isEmpty, !searching, text.count >= 2 {
                Text("Nothing yet. Keep typing, or add a city.").font(DG.font(13.5)).foregroundStyle(DG.sub).padding(16)
            }
        }
        .dgGlass(radius: DG.R.card)
        .padding(.top, 10)
    }

    /// The typed part of a name in bold, the rest regular.
    private func highlighted(_ title: String) -> Text {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, title.lowercased().hasPrefix(q.lowercased()) else { return Text(title).font(DG.font(16, .semibold)) }
        return Text(String(title.prefix(q.count))).font(DG.font(16, .bold)) + Text(String(title.dropFirst(q.count))).font(DG.font(16, .regular))
    }

    private func row(systemImage: String, ghost: Bool, title: String, sub: String, place: Place, remove: (() -> Void)? = nil,
                     action: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ghost ? DG.sub : DG.inkColor(.low))
                        .frame(width: 40, height: 40)
                        .background(ghost ? DG.ink.opacity(0.06) : DG.path.opacity(0.1), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        highlighted(title).foregroundStyle(DG.ink).lineLimit(1)
                        if !sub.isEmpty, sub != title { Text(sub).font(DG.T.rowSub).foregroundStyle(DG.sub).lineLimit(1) }
                    }
                    Spacer(minLength: 6)
                    if let d = away(place) {
                        Text(d).font(DG.font(13, .medium)).foregroundStyle(DG.sub).monospacedDigit()
                    }
                }
                .padding(.leading, 14).padding(.trailing, remove == nil ? 14 : 2).frame(minHeight: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let remove {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(DG.faint)
                        .padding(12).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(title)")
                .accessibilityIdentifier("remove-place")
            }
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
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        if let coord = Self.parseCoordinates(trimmed) {
            results = [Suggestion(name: coord.pretty, lat: coord.latitude, lon: coord.longitude)]
            return
        }
        guard trimmed.count >= 2 else { results = []; return }
        seq += 1
        let mine = seq
        task = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            searching = true
            defer { if mine == seq { searching = false } }
            if let found = try? await Search.suggest(trimmed, near: model.here), mine == seq {
                results = found
            }
        }
    }

    private func submit() async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let coord = Self.parseCoordinates(trimmed) {
            pick(Place(name: coord.pretty, coordinate: coord, kind: .recent))
            return
        }
        if let first = localMatches.first { pick(first); return }
        if let first = results.first {
            pick(Place(name: first.name, coordinate: first.coordinate, kind: .recent))
            return
        }
        searching = true
        defer { searching = false }
        do {
            if let first = try await Search.geocode(trimmed).first {
                pick(Place(name: first.name, coordinate: first.coordinate, kind: .recent))
            } else {
                model.errorMessage = "Nothing found for \"\(trimmed)\". Try adding a city."
            }
        } catch {
            // No answer is not the same as no match.
            model.errorMessage = !model.online || Connectivity.isOffline(error) ? OfflineText.search
                : "Search is not answering right now. Try again in a moment."
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
