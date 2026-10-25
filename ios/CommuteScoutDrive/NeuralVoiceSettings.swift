import AVFoundation
import CryptoKit
import SwiftUI

/// The top of Settings > Voice: the CommuteScout voices. Each pack has
/// one row to download, cancel, resume or delete it, and each voice a
/// row with a preview that streams before anything is downloaded. Once
/// the pack is on the phone its voices are picked like the system ones.
struct CommuteScoutVoicesSections: View {
    @ObservedObject private var packs = VoicePacks.shared
    @ObservedObject private var connectivity = Connectivity.shared
    @ObservedObject var previews: VoicePreviewPlayer
    /// The voice id that is picked, if it is a CommuteScout voice.
    let selected: String?
    let pick: (String) -> Void

    @State private var askCellular: VoiceCatalog.Pack?
    @State private var askDelete: VoiceCatalog.Pack?
    @State private var noSpace: String?

    private var offered: [VoiceCatalog.Pack] { packs.catalog?.offeredPacks() ?? [] }

    var body: some View {
        ForEach(Array(offered.enumerated()), id: \.element.id) { index, pack in
            Section {
                packRow(pack)
                ForEach(pack.voices) { v in voiceRow(v, in: pack) }
            } header: {
                if index == 0 { Text("CommuteScout voices") }
            } footer: {
                if index == offered.count - 1 { footer(pack) }
            }
        }
        .confirmationDialog("Download on cellular data?", isPresented: Binding(get: { askCellular != nil }, set: { if !$0 { askCellular = nil } }),
                            titleVisibility: .visible, presenting: askCellular) { pack in
            Button("Download on cellular") { packs.download(pack.id, cellular: true) }
            Button("Wait for Wi-Fi") { packs.download(pack.id, cellular: false) }
            Button("Cancel", role: .cancel) {}
        } message: { pack in
            Text("\(pack.title) are \(VoicePackFiles.label(pack.downloadSize)). Downloading on Wi-Fi avoids using your data plan.")
        }
        .confirmationDialog("Delete \(askDelete?.title.lowercased() ?? "voices")?", isPresented: Binding(get: { askDelete != nil }, set: { if !$0 { askDelete = nil } }),
                            titleVisibility: .visible, presenting: askDelete) { pack in
            Button("Delete \(VoicePackFiles.label(pack.downloadSize))", role: .destructive) { delete(pack) }
            Button("Cancel", role: .cancel) {}
        } message: { pack in
            Text("This frees \(VoicePackFiles.label(max(VoicePackFiles.bytesOnDisk(pack), 0))) on this phone. You can download \(pack.title.lowercased()) again at any time.")
        }
        .alert("Not enough space", isPresented: Binding(get: { noSpace != nil }, set: { if !$0 { noSpace = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(noSpace ?? "") }
    }

    // MARK: the pack row

    @ViewBuilder
    private func packRow(_ pack: VoiceCatalog.Pack) -> some View {
        let state = packs.state(pack.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                SettingsIcon(symbol: "waveform.badge.plus", color: .pink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.title).font(.headline)
                    Text(summary(pack)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                packAction(pack, state)
            }
            switch state {
            case let .downloading(done, total):
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .accessibilityIdentifier("voices-progress-\(pack.id)")
                Text(progressText(done, total, waiting: !connectivity.onWifi && !cellularAllowed(pack)))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            case let .paused(done, total):
                ProgressView(value: Double(done), total: Double(max(total, 1))).tint(.secondary)
                HStack {
                    Text("Paused: \(VoicePackFiles.label(done)) of \(VoicePackFiles.label(total))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Button("Delete", role: .destructive) { askDelete = pack }
                        .buttonStyle(.borderless).font(.caption)
                        .accessibilityIdentifier("voices-delete-\(pack.id)")
                }
            case let .failed(why):
                Text(why).font(.caption).foregroundStyle(.red)
            case .installed:
                HStack {
                    Label("Downloaded, \(VoicePackFiles.label(pack.downloadSize))", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Delete", role: .destructive) { askDelete = pack }
                        .buttonStyle(.borderless).font(.caption)
                        .accessibilityIdentifier("voices-delete-\(pack.id)")
                }
            case .none:
                EmptyView()
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func packAction(_ pack: VoiceCatalog.Pack, _ state: VoicePacks.State) -> some View {
        switch state {
        case .none, .failed:
            Button { start(pack) } label: {
                Text("Download \(VoicePackFiles.label(pack.downloadSize))").font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered).buttonBorderShape(.capsule)
            .accessibilityIdentifier("voices-download-\(pack.id)")
        case .downloading:
            Button { packs.pause(pack.id) } label: {
                Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Cancel download")
            .accessibilityIdentifier("voices-cancel-\(pack.id)")
        case .paused:
            Button { start(pack) } label: { Text("Resume").font(.subheadline.weight(.semibold)) }
                .buttonStyle(.bordered).buttonBorderShape(.capsule)
                .accessibilityIdentifier("voices-resume-\(pack.id)")
        case .installed:
            EmptyView()
        }
    }

    /// "8 voices, US and UK English, 145 MB".
    private func summary(_ pack: VoiceCatalog.Pack) -> String {
        let accents = Set(pack.voices.map { VoicePick.regionCode($0.accent) ?? "" })
        let where_ = accents == ["US"] ? "US English" : accents == ["GB"] ? "UK English" : "US and UK English"
        return "\(pack.voices.count) voices, \(where_), \(VoicePackFiles.label(pack.downloadSize))"
    }

    private func progressText(_ done: Int64, _ total: Int64, waiting: Bool) -> String {
        let pct = total > 0 ? Int(Double(done) / Double(total) * 100) : 0
        let base = "\(VoicePackFiles.label(done)) of \(VoicePackFiles.label(total)) (\(pct)%)"
        return waiting ? base + ". Waiting for Wi-Fi." : base
    }

    private func cellularAllowed(_ pack: VoiceCatalog.Pack) -> Bool {
        UserDefaults.standard.bool(forKey: "cs.voices.cellular.\(pack.id)")
    }

    private func start(_ pack: VoiceCatalog.Pack) {
        if case let .noSpace(needed) = packs.problem(pack.id) {
            noSpace = "\(pack.title) need \(VoicePackFiles.label(needed)) free on this phone. Free up some space and try again."
            return
        }
        if connectivity.online, !connectivity.onWifi {
            askCellular = pack
        } else {
            packs.download(pack.id, cellular: false)
        }
    }

    private func delete(_ pack: VoiceCatalog.Pack) {
        // The voice in use goes with its pack: back to Automatic.
        if let s = selected, pack.voices.contains(where: { $0.id == s }) { pick("") }
        previews.stop()
        packs.delete(pack.id)
    }

    // MARK: a voice row

    private func voiceRow(_ v: VoiceCatalog.Voice, in pack: VoiceCatalog.Pack) -> some View {
        let installed = packs.state(pack.id) == .installed
        let isSelected = installed && selected == v.id
        return HStack(spacing: 12) {
            Button { previews.toggle(v) } label: {
                ZStack {
                    if previews.loading == v.id {
                        ProgressView()
                    } else {
                        Image(systemName: previews.playing == v.id ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title2).foregroundStyle(Color.accentColor)
                    }
                }
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderless)
            .disabled(v.preview == nil)
            .accessibilityLabel(previews.playing == v.id ? "Stop the sample of \(v.name)" : "Play a sample of \(v.name)")
            .accessibilityIdentifier("voices-preview-\(v.id)")
            Button { if installed { pick(v.id) } } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.name).foregroundStyle(installed ? .primary : .secondary)
                        Text(Self.detail(v)).font(.caption).foregroundStyle(.secondary)
                        Text("Computer-generated voice").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color.accentColor)
                        .opacity(isSelected ? 1 : 0)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!installed)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("voice-\(v.id)")
        }
    }

    /// "English (UK), female".
    static func detail(_ v: VoiceCatalog.Voice) -> String {
        "\(VoicePick.accent(v.accent)), \(v.gender)"
    }

    private func footer(_ pack: VoiceCatalog.Pack) -> some View {
        Text("CommuteScout voices are computer-generated voices that run on this phone and need no signal once downloaded. One download adds every voice in the set. Play a sample before you download. When a trip starts, the first instructions may be said in the system voice while the rest are prepared.")
    }
}

/// Streams a voice's sample clip from the release, so a voice can be
/// heard before its pack is downloaded. One sample at a time.
@MainActor
final class VoicePreviewPlayer: ObservableObject {
    @Published private(set) var playing: String?
    @Published private(set) var loading: String?
    private var player: AVPlayer?
    private var watch: NSKeyValueObservation?
    private var end: NSObjectProtocol?

    func toggle(_ v: VoiceCatalog.Voice) {
        if playing == v.id || loading == v.id { stop(); return }
        play(v)
    }

    private var fetch: URLSessionDataTask?

    /// Where a sample is kept once fetched, so a second tap plays at once.
    private static func cached(_ v: VoiceCatalog.Voice) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("voice-previews")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(v.id).m4a")
    }

    /// Samples are small (about 60 KB). GitHub serves them as
    /// application/octet-stream behind a redirect, which AVPlayer will
    /// not stream, so the sample is fetched, checked against its hash,
    /// and played from the cache.
    func play(_ v: VoiceCatalog.Voice) {
        stop()
        guard let preview = v.preview else { return }
        loading = v.id
        let local = Self.cached(v)
        if VoicePackFiles.size(local) == preview.size { start(v, local); return }
        var req = URLRequest(url: preview.url, timeoutInterval: 15)
        req.allowsExpensiveNetworkAccess = true
        fetch = URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            Task { @MainActor in
                guard let self, self.loading == v.id else { return }
                guard let data, Int64(data.count) == preview.size,
                      SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == preview.sha256,
                      (try? data.write(to: local, options: .atomic)) != nil else {
                    DriveLog.note("voices: sample of \(v.name) failed to load: \(error?.localizedDescription ?? "bad download")")
                    self.stop()
                    return
                }
                self.start(v, local)
            }
        }
        fetch?.resume()
    }

    private func start(_ v: VoiceCatalog.Voice, _ url: URL) {
        SpeechFocus.shared.take()
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        watch = p.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            Task { @MainActor in
                guard let self, self.player === p else { return }
                if p.timeControlStatus == .playing { self.loading = nil; self.playing = v.id }
                if p.currentItem?.status == .failed {
                    DriveLog.note("voices: sample of \(v.name) failed to play: \(p.currentItem?.error?.localizedDescription ?? "unknown")")
                    self.stop()
                }
            }
        }
        end = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        p.play()
    }

    func stop() {
        fetch?.cancel()
        fetch = nil
        player?.pause()
        player = nil
        watch = nil
        if let end { NotificationCenter.default.removeObserver(end) }
        end = nil
        playing = nil
        loading = nil
        if !Voice.synth.isSpeaking, !NeuralSpeaker.shared.busy { SpeechFocus.shared.release() }
    }
}

/// Settings > About > Voice licenses: who made each voice and under
/// what terms, and the licenses of the speech engine in the app.
struct VoiceLicensesView: View {
    @ObservedObject private var packs = VoicePacks.shared

    var body: some View {
        Form {
            Section {
                Text("CommuteScout voices run on the sherpa-onnx speech engine with ONNX Runtime. Each set of voices comes from the project named below, under its own license.")
                    .font(.subheadline)
            }
            ForEach(packs.catalog?.offeredPacks() ?? []) { pack in
                Section(pack.title) {
                    Text(pack.attribution).font(.subheadline)
                    LabeledContent("Model", value: pack.engineVersion)
                    LabeledContent("License", value: pack.license.name)
                    if let url = URL(string: pack.license.url) {
                        Link(destination: url) { Label("License source", systemImage: "arrow.up.right.square") }
                    }
                    if pack.isSupertonic {
                        Text("Use of these voices is subject to the use restrictions in Attachment A of the OpenRAIL-M license.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if packs.state(pack.id) == .installed {
                        ForEach(["NOTICE", "LICENSE"], id: \.self) { name in
                            NavigationLink(name == "NOTICE" ? "Notice" : "License text") {
                                LicenseTextView(title: "\(pack.title): \(name == "NOTICE" ? "notice" : "license")",
                                                text: Self.packText(pack, name))
                            }
                        }
                    } else {
                        Text("The full license and notice come with the voices and appear here after you download them.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Speech engine") {
                NavigationLink("sherpa-onnx, Apache License 2.0") {
                    LicenseTextView(title: "sherpa-onnx", text: Self.bundled("sherpa-onnx-LICENSE"))
                }
                NavigationLink("ONNX Runtime, MIT License") {
                    LicenseTextView(title: "ONNX Runtime", text: Self.bundled("onnxruntime-LICENSE"))
                }
            }
        }
        .navigationTitle("Voice licenses")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func packText(_ pack: VoiceCatalog.Pack, _ name: String) -> String {
        let url = VoicePackFiles.directory(pack.id).appendingPathComponent(name)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "The file is missing. Download the voices again to restore it."
    }

    static func bundled(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }
}

struct LicenseTextView: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
