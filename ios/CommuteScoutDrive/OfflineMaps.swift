import SwiftUI

/// Maps saved on the phone for driving with no signal: the trip
/// corridors the app saved on its own, and whole states the driver
/// chooses here. A state is big, and the sheet says how big before
/// anything downloads.
struct OfflineMapsView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirming: MapFiles.Manifest.StateFile?

    private var files: MapFiles { model.mapFiles }

    var body: some View {
        Form {
            Section {
                Text("With no signal the map draws from a file saved here: the corridor saved for the current trip, or a whole state. Guidance and spoken alerts work either way; this is the map underneath.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let local = files.usingLocal {
                    Label("Drawing from \(local.name) right now", systemImage: "wifi.slash").font(.footnote)
                }
            }
            Section("Saved for trips") {
                let corridors = files.files.filter { $0.kind == .corridor }.sorted { $0.savedAt > $1.savedAt }
                if corridors.isEmpty {
                    Text("None yet. A trip's map is saved when it starts, on Wi-Fi, or from the route card on mobile data.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(corridors) { c in
                    NavigationLink { SavedMapDetail(file: c) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name)
                            Text("\(c.sizeText), saved \(c.savedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                if let m = files.manifest {
                    ForEach(m.states) { s in stateRow(s) }
                } else if files.progress.isEmpty {
                    Text(model.online ? "The list of states is loading." : "The list of states needs a signal.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Whole states")
            } footer: {
                Text("A whole state is the entire map at full detail, which can be several gigabytes. Download on Wi-Fi, and only the states you drive in.")
            }
            if files.bytesOnDisk > 0 {
                Section {
                    Text("Using \(ByteCountFormatter.string(fromByteCount: files.bytesOnDisk, countStyle: .file)) on this phone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Offline maps")
        .task { await files.refreshManifest() }
        .confirmationDialog(confirming.map { "Download \($0.name)?" } ?? "", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible, presenting: confirming) { s in
            Button("Download \(sizeText(s))") { Task { await files.downloadState(s) } }
            Button("Cancel", role: .cancel) {}
        } message: { s in
            Text("This is the whole map of \(s.name) at full detail, \(sizeText(s)). It may take a while and should go over Wi-Fi.")
        }
        .onChange(of: files.lastNotice) { n in if let n { model.toast = n; files.lastNotice = nil } }
    }

    private func sizeText(_ s: MapFiles.Manifest.StateFile) -> String {
        s.bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "size unknown"
    }

    @ViewBuilder private func stateRow(_ s: MapFiles.Manifest.StateFile) -> some View {
        HStack {
            if let saved = files.has(state: s.code) {
                NavigationLink { SavedMapDetail(file: saved) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name)
                        Label("Saved, \(saved.sizeText)", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name)
                    Text(files.progress["state-\(s.code)"].map { "Downloading, \(Int($0 * 100))%" } ?? sizeText(s))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let p = files.progress["state-\(s.code)"] {
                ProgressView(value: p).frame(width: 90)
            } else if files.has(state: s.code) != nil {
                EmptyView()
            } else {
                Button { confirming = s } label: { Image(systemName: "arrow.down.circle") }.buttonStyle(.borderless)
                    .disabled(!model.online)
                    .accessibilityIdentifier("download-\(s.code)")
            }
        }
    }
}
