import CoreLocation
import SwiftUI

// The sheets a driver opens mid-trip: pick a place (a stop on the way,
// or a new destination) and "Your trip", which shows where the trip
// goes and lets it change. Rows are large on purpose: these are used at
// a red light.

/// Which sheet the trip bar has open.
enum NavSheet: String, Identifiable {
    case stop, destination, trip
    var id: String { rawValue }
}

/// Pick a place while driving. With nothing typed it lists Home, Work,
/// favorites and recent places; the quick searches look near the driver.
struct PlacePickSheet: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let sub: String
    let quick: Bool
    let exclude: [Place]
    let onPick: (Place) -> Void
    let onClose: () -> Void

    @State private var text = ""
    @State private var results: [Suggestion] = []
    @State private var searching = false
    @State private var asked = false
    @State private var seq = 0
    @FocusState private var focused: Bool

    private static let quickSearches = [("fuelpump.fill", "Gas", "gas station"), ("bolt.fill", "Charging", "ev charging"),
                                        ("cup.and.saucer.fill", "Coffee", "coffee"), ("fork.knife", "Food", "restaurant")]

    private struct Row: Identifiable {
        let icon: String
        let name: String
        let sub: String?
        let place: Place
        var id: String { place.id }
    }

    private func tail(_ name: String) -> String? {
        guard let i = name.firstIndex(of: ",") else { return nil }
        let t = name[name.index(after: i)...].trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    private var rows: [Row] {
        let all: [Row]
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            all = (model.places.home.map { [Row(icon: "home", name: "Home", sub: $0.name, place: $0)] } ?? [])
                + (model.places.work.map { [Row(icon: "work", name: "Work", sub: $0.name, place: $0)] } ?? [])
                + model.places.saved.prefix(3).map { Row(icon: "star.fill", name: $0.shortName, sub: tail($0.name), place: $0) }
                + model.places.recents.prefix(5).map { Row(icon: "recent", name: $0.shortName, sub: tail($0.name), place: $0) }
        } else {
            all = results.map { s in
                let p = Place(name: s.name, coordinate: s.coordinate, kind: .recent)
                return Row(icon: "mappin", name: p.shortName, sub: tail(s.name), place: p)
            }
        }
        return Array(all.filter { r in !exclude.contains { AlertsEngine.meters($0.coordinate, r.place.coordinate) < 30 } }.prefix(8))
    }

    private var note: String? {
        if !rows.isEmpty { return text.isEmpty ? nil : "The trip is not changed until you confirm." }
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return "Search for a place, or tap one of the quick searches." }
        if searching || !asked { return nil }
        return model.online ? "Nothing found for that. Try other words, or add a city." : OfflineText.search
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(DG.T.sheetTitle).foregroundStyle(DG.ink)
                    Text(sub).font(DG.T.meta).foregroundStyle(DG.sub).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button(action: onClose) {
                    DGIconView(name: "close", size: 18, stroke: 2.4).foregroundStyle(DG.ink)
                        .frame(width: 40, height: 40).background(DG.ink.opacity(0.06), in: Circle())
                }
                .buttonStyle(DGPressStyle()).accessibilityLabel("Close").accessibilityIdentifier("place-pick-close")
            }
            .padding(.horizontal, 20).padding(.top, 22)

            HStack(spacing: 10) {
                DGIconView(name: "search", size: 20).foregroundStyle(DG.sub)
                TextField("Search a place or address", text: $text)
                    .font(DG.font(17, .medium)).foregroundStyle(DG.ink)
                    .submitLabel(.search).autocorrectionDisabled().focused($focused)
                    .onSubmit { focused = false; search(text, wait: 0) }
                    .onChange(of: text) { search($0) }
                    .accessibilityIdentifier("place-pick-search")
                if searching || model.tripChanging { ProgressView().padding(.trailing, 8) }
                else if !text.isEmpty {
                    Button { text = ""; results = []; asked = false } label: {
                        DGIconView(name: "close", size: 16, stroke: 2.4).foregroundStyle(DG.sub).frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.leading, 16).padding(.trailing, 6).frame(height: 52)
            .background(DG.ink.opacity(0.05), in: Capsule())
            .padding(.horizontal, 16).padding(.top, 14)

            if quick {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.quickSearches, id: \.1) { icon, label, words in
                            let on = text == words
                            Button { focused = false; text = words; search(words, wait: 0) } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                                    Text(label).font(DG.font(14, .semibold))
                                }
                                .foregroundStyle(on ? DGTone.low.ink : DG.ink)
                                .padding(.leading, 12).padding(.trailing, 14).frame(height: 40)
                                .background(on ? DG.path.opacity(0.14) : DG.ink.opacity(0.05), in: Capsule())
                            }
                            .buttonStyle(DGPressStyle()).accessibilityIdentifier("quick-\(label)")
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 12)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { Rectangle().fill(DG.hair).frame(height: 0.5).padding(.leading, 74).padding(.trailing, 18) }
                        Button { focused = false; onPick(r.place) } label: {
                            HStack(spacing: 14) {
                                DGIconView(name: r.icon, size: 20).foregroundStyle(DG.path)
                                    .frame(width: 42, height: 42).background(DG.path.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.name).font(DG.T.rowTitle).foregroundStyle(DG.ink).lineLimit(1)
                                    if let s = r.sub, s != r.name { Text(s).font(DG.T.rowSub).foregroundStyle(DG.sub).lineLimit(1) }
                                }
                                Spacer(minLength: 8)
                                if let here = model.here {
                                    Text(Units.distance(AlertsEngine.meters(here, r.place.coordinate)))
                                        .font(DG.T.rowTitle).foregroundStyle(DG.ink).monospacedDigit()
                                }
                            }
                            .padding(.horizontal, 18).frame(minHeight: 64).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).disabled(model.tripChanging).accessibilityIdentifier("place-pick-row")
                    }
                    if let note {
                        Text(note).font(DG.font(12.5, .medium)).foregroundStyle(DG.faint)
                            .padding(.horizontal, 20).padding(.top, 12)
                    }
                }
                .padding(.top, 8).padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("place-pick")
    }

    private func search(_ raw: String, wait: UInt64 = 160) {
        let t = raw.trimmingCharacters(in: .whitespaces)
        seq += 1
        let mine = seq
        guard t.count >= 2 else { results = []; searching = false; asked = false; return }
        Task {
            try? await Task.sleep(nanoseconds: wait * 1_000_000)
            guard mine == seq else { return }
            searching = true
            let found = try? await Search.suggest(t, near: model.here)
            guard mine == seq else { return }
            results = found ?? []
            asked = true
            searching = false
        }
    }
}

/// Where this trip goes: from here, through any stops, to the
/// destination. Each part can change.
struct YourTripSheet: View {
    @EnvironmentObject var model: AppModel
    let destination: Place
    let arrive: String?
    let onChangeDestination: () -> Void
    let onAddStop: () -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your trip").font(DG.T.sheetTitle).foregroundStyle(DG.ink)
                        Text("Change where you are going").font(DG.T.meta).foregroundStyle(DG.sub)
                    }
                    Spacer(minLength: 8)
                    Button(action: onClose) {
                        DGIconView(name: "close", size: 18, stroke: 2.4).foregroundStyle(DG.ink)
                            .frame(width: 40, height: 40).background(DG.ink.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(DGPressStyle()).accessibilityLabel("Close").accessibilityIdentifier("trip-sheet-close")
                }
                .padding(.horizontal, 20).padding(.top, 22)

                VStack(spacing: 0) {
                    row(title: "From here", sub: nil) {
                        Circle().fill(DG.path).frame(width: 14, height: 14).frame(width: 32, height: 32)
                    } trail: { EmptyView() }
                    ForEach(Array(model.tripStops.enumerated()), id: \.element.id) { i, s in
                        divider
                        row(title: s.shortName, sub: tail(s.name)) { StopDisc(n: i + 1) } trail: {
                            if model.tripChanging { ProgressView().frame(width: 40, height: 40) } else {
                                Button { model.removeStop(s) } label: {
                                    DGIconView(name: "close", size: 16, stroke: 2.4).foregroundStyle(DG.sub).frame(width: 40, height: 40)
                                }
                                .accessibilityLabel("Remove \(s.shortName)").accessibilityIdentifier("remove-stop")
                            }
                        }
                    }
                    divider
                    row(title: destination.shortName, sub: arrive.map { "Arrive \($0)" }) {
                        DGIconView(name: "mappin", size: 17).foregroundStyle(.white)
                            .frame(width: 32, height: 32).background(DG.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } trail: {
                        Button(action: onChangeDestination) {
                            Text("Change").font(DG.font(14, .semibold)).foregroundStyle(DGTone.low.ink)
                                .padding(.horizontal, 16).frame(height: 40).background(DG.path.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(DGPressStyle()).accessibilityIdentifier("change-destination")
                    }
                }
                .background(DG.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 16).padding(.top, 14)

                Button(action: onAddStop) { Label("Add a stop", systemImage: "mappin") }
                    .buttonStyle(DGButtonStyle(kind: .glass, height: 52))
                    .padding(.horizontal, 16).padding(.top, 10)
                    .accessibilityIdentifier("trip-add-stop")

                Text("Map").font(DG.T.section).foregroundStyle(DG.sub).padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 8)
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("View").font(DG.T.rowTitle).foregroundStyle(DG.ink)
                        Text(model.prefs.is3D ? "3D, tilted toward the road ahead" : "2D, straight down").font(DG.T.rowSub).foregroundStyle(DG.sub)
                    }
                    Spacer()
                    DGModesPill(is3D: model.prefs.is3D) { withAnimation(DG.tilt) { model.toggle3D() } }
                }
                .padding(.leading, 16).padding(.trailing, 10).padding(.vertical, 8)
                .background(DG.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 16).padding(.bottom, 20)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip-sheet")
    }

    private var divider: some View { Rectangle().fill(DG.hair).frame(height: 0.5).padding(.leading, 62) }

    private func tail(_ name: String) -> String? {
        guard let i = name.firstIndex(of: ",") else { return nil }
        let t = name[name.index(after: i)...].trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    private func row<Lead: View, Trail: View>(title: String, sub: String?, @ViewBuilder lead: () -> Lead, @ViewBuilder trail: () -> Trail) -> some View {
        HStack(spacing: 14) {
            lead()
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(DG.T.rowTitle).foregroundStyle(DG.ink).lineLimit(1)
                if let sub { Text(sub).font(DG.T.rowSub).foregroundStyle(DG.sub).lineLimit(1) }
            }
            Spacer(minLength: 8)
            trail()
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 8).frame(minHeight: 60)
    }
}
