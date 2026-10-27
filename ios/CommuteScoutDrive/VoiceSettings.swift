import AVFoundation
import SwiftUI

/// Settings > Voice: who says the turns and the alerts, how fast and at
/// what pitch. One list holds every voice: Automatic, the CommuteScout
/// voices, and the voices iOS keeps on the phone. A tap on a voice picks
/// it and plays a sample in it. A CommuteScout voice that is not on the
/// phone yet plays its sample first and asks before the download; the
/// downloads themselves are under Downloaded voices, to cancel or delete.
struct VoiceSettings: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var voices: [VoiceOption] = []
    @State private var allAccents = false
    @State private var offer: VoiceCatalog.Voice?
    @State private var noSpace: String?
    @StateObject private var previews = VoicePreviewPlayer()
    @ObservedObject private var packs = VoicePacks.shared
    @ObservedObject private var connectivity = Connectivity.shared

    private var prefs: Prefs { model.prefs }

    /// English voices worth offering, best first.
    private var offered: [VoiceOption] { VoicePick.offered(voices, language: Voice.language) }
    private var region: String? { Voice.region?.uppercased() }
    private func isLocal(_ language: String) -> Bool { VoicePick.regionCode(language) == region }

    private var neuralPacks: [VoiceCatalog.Pack] { packs.catalog?.offeredPacks() ?? [] }
    private var neuralVoices: [(pack: VoiceCatalog.Pack, voice: VoiceCatalog.Voice)] {
        neuralPacks.flatMap { p in p.voices.map { (p, $0) } }
    }

    /// Voices with the phone's own accent unless all are asked for, and
    /// the picked voice whatever its accent. With no voice for the region
    /// at all, every accent.
    private var anyLocal: Bool { offered.contains { isLocal($0.language) } || neuralVoices.contains { isLocal($0.voice.accent) } }
    private func show(_ language: String, _ id: String) -> Bool { allAccents || !anyLocal || isLocal(language) || id == prefs.voiceId }
    private var hasOtherAccents: Bool {
        anyLocal && (offered.contains { !isLocal($0.language) } || neuralVoices.contains { !isLocal($0.voice.accent) })
    }

    private var speaking: VoiceOption? { Voice.resolve(saved: prefs.voiceId, among: voices) }
    private var best: VoiceOption? { VoicePick.best(offered, region: region, systemDefault: Voice.systemDefault) }
    /// The CommuteScout voice that speaks, if one does.
    private var neural: (pack: VoiceCatalog.Pack, voice: VoiceCatalog.Voice)? {
        _ = packs.states   // read so the page follows a download or a delete
        return packs.catalog?.neuralVoice(saved: prefs.voiceId, installed: VoicePacks.installedIds)
    }
    /// The CommuteScout voice picked, on the phone or still downloading.
    private var pickedNeural: (pack: VoiceCatalog.Pack, voice: VoiceCatalog.Voice)? {
        neuralVoices.first { $0.voice.id == prefs.voiceId }
    }
    /// What Automatic would pick among the CommuteScout voices.
    private var automaticNeural: VoiceCatalog.Voice? {
        _ = packs.states
        return packs.catalog?.neuralVoice(saved: "", installed: VoicePacks.installedIds)?.voice
    }
    /// Automatic: nothing picked, or the pick is gone from the phone.
    private var automatic: Bool { !offered.contains { $0.id == prefs.voiceId } && pickedNeural == nil }

    /// What a drive sounds like, in the driver's units.
    private var sample: String { "In \(Units.spoken(805)), turn right onto Main Street. Police reported ahead." }

    var body: some View {
        dialogs(form)
            .onAppear {
                reload()
                // Ready the sample in the voice in use, so Test voice speaks at once.
                if Voice.neural != nil, !model.state.isNavigating { NeuralVoices.shared.prerender([(sample, -1)]) }
            }
            .onDisappear { previews.stop() }
            .onChange(of: scenePhase) { phase in
                if phase == .active { reload() }
            }
            .onReceive(voicesChanged) { _ in reload() }
    }

    private var form: some View {
        Form {
            voiceSection
            speedSection
            VoicePackSection(previews: previews, picked: prefs.voiceId) { pick($0) }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var offerTitle: String { offer.map { "Download \($0.name)?" } ?? "" }
    private var offerShown: Binding<Bool> { Binding(get: { offer != nil }, set: { if !$0 { offer = nil } }) }
    private var noSpaceShown: Binding<Bool> { Binding(get: { noSpace != nil }, set: { if !$0 { noSpace = nil } }) }

    private func dialogs<Content: View>(_ content: Content) -> some View {
        content
        .confirmationDialog(offerTitle, isPresented: offerShown, titleVisibility: .visible, presenting: offer) { v in
            if connectivity.online, !connectivity.onWifi {
                Button("Download on cellular") { choose(v, cellular: true) }
                Button("Download on Wi-Fi") { choose(v, cellular: false) }
            } else {
                Button("Download") { choose(v, cellular: false) }
                    .accessibilityIdentifier("voice-offer-download")
            }
            Button("Cancel", role: .cancel) { previews.stop() }
        } message: { v in
            Text(offerText(v))
        }
        .alert("Not enough space", isPresented: noSpaceShown) {
            Button("OK", role: .cancel) {}
        } message: { Text(noSpace ?? "") }
    }

    private var automaticDetail: String {
        if let v = automaticNeural { return "Uses \(v.name), a CommuteScout voice" }
        if let v = best { return "Uses \(v.name), the best voice on this phone" }
        return "Uses the system voice"
    }

    private var voiceSection: some View {
        Section {
            row("Automatic", automaticDetail, selected: automatic, id: "voice-automatic") { pick("") }
            ForEach(neuralVoices.filter { show($0.voice.accent, $0.voice.id) }, id: \.voice.id) { item in
                neuralRow(item.voice, in: item.pack)
            }
            ForEach(offered.filter { show($0.language, $0.id) }) { v in
                row(v.name, detail(v), quality: v.quality, selected: !automatic && prefs.voiceId == v.id, id: "voice-\(v.id)") { pick(v.id) }
            }
            if hasOtherAccents {
                Toggle("Show all English accents", isOn: $allAccents)
                    .accessibilityIdentifier("voice-all-accents")
            }
        } header: { Text("Voice") } footer: {
            Text("Tap a voice to choose it and hear it. CommuteScout voices are computer-generated, run on this phone, and need no signal once downloaded. Voices you add to iOS in Settings > Accessibility > Spoken Content also appear here.")
        }
    }

    private var speedSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Speed", value: percent(prefs.voiceRate, of: Voice.defaultRate))
                Slider(value: binding(\.voiceRate, step: 0.01), in: Voice.rateRange) { Text("Speed") }
                    minimumValueLabel: { Image(systemName: "tortoise.fill").foregroundStyle(.secondary) }
                    maximumValueLabel: { Image(systemName: "hare.fill").foregroundStyle(.secondary) }
                    onEditingChanged: { if !$0 { play() } }
                    .accessibilityIdentifier("voice-speed")
            }
            if neural == nil {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Pitch", value: percent(prefs.voicePitch, of: Voice.defaultPitch))
                    Slider(value: binding(\.voicePitch, step: 0.05), in: Voice.pitchRange) { Text("Pitch") }
                        minimumValueLabel: { Text("Low").font(.caption).foregroundStyle(.secondary) }
                        maximumValueLabel: { Text("High").font(.caption).foregroundStyle(.secondary) }
                        onEditingChanged: { if !$0 { play() } }
                        .accessibilityIdentifier("voice-pitch")
                }
            }
            Button { play() } label: { Label("Test voice", systemImage: "play.circle.fill") }
                .accessibilityIdentifier("voice-test")
            Button("Reset to normal") {
                prefs.voiceRate = Voice.defaultRate
                prefs.voicePitch = Voice.defaultPitch
                prefs.objectWillChange.send()
            }
            .disabled(prefs.voiceRate == Voice.defaultRate && prefs.voicePitch == Voice.defaultPitch)
            .accessibilityIdentifier("voice-reset")
        } header: { Text("Speed and pitch") } footer: { Text(speakingNote) }
    }

    // MARK: rows

    private func row(_ title: String, _ subtitle: String, quality: VoiceOption.Quality? = nil, status: String? = nil,
                     selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    if let status { Text(status).font(.caption).foregroundStyle(Color.accentColor).monospacedDigit() }
                }
                Spacer(minLength: 8)
                if let quality, quality > .standard { VoiceQualityBadge(quality: quality) }
                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color.accentColor)
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    /// A CommuteScout voice. Not on the phone: its size, and while its
    /// set downloads, how far along it is.
    private func neuralRow(_ v: VoiceCatalog.Voice, in pack: VoiceCatalog.Pack) -> some View {
        let state = packs.state(pack.id)
        var subtitle = "\(VoicePick.accent(v.accent)), \(v.gender). Computer-generated CommuteScout voice"
        var status: String?
        switch state {
        case .installed: break
        case let .downloading(done, total): status = "Downloading \(VoicePackFiles.percent(done, total))"
        case let .paused(done, total): status = "Paused at \(VoicePackFiles.percent(done, total))"
        case .failed: status = "Download did not finish"
        case .none: subtitle += ", \(VoicePackFiles.label(pack.downloadSize)) download"
        }
        if previews.loading == v.id || previews.playing == v.id { status = "Playing a sample" }
        return row(v.name, subtitle, status: status, selected: prefs.voiceId == v.id, id: "voice-\(v.id)") { tap(v, in: pack) }
    }

    /// "English (UK), female".
    private func detail(_ v: VoiceOption) -> String {
        [v.accent, v.gender?.lowercased()].compactMap { $0 }.joined(separator: ", ")
    }

    private var speakingNote: String {
        if let p = pickedNeural, neural == nil {
            return "\(p.voice.name) speaks once \(p.pack.title.lowercased()) finish downloading. Until then, \(speaking?.name ?? "the system voice") speaks."
        }
        if neural != nil { return "Turn instructions and road alerts are both spoken in this voice. CommuteScout voices keep their own pitch." }
        return "Turn instructions and road alerts are both spoken in this voice."
    }

    private func offerText(_ v: VoiceCatalog.Voice) -> String {
        guard let pack = neuralVoices.first(where: { $0.voice.id == v.id })?.pack else { return "" }
        let others = pack.voices.count - 1
        return "\(v.name) comes in \(pack.title.lowercased()), a \(VoicePackFiles.label(pack.downloadSize)) download with \(others) more voices. Until it finishes, the system voice speaks."
    }

    private func percent(_ v: Double, of normal: Double) -> String {
        let p = Int((v / normal * 100).rounded())
        return p == 100 ? "Normal" : "\(p)%"
    }

    /// A slider's value, kept to whole steps. The slider itself moves
    /// smoothly; a stepped Slider draws a dot for every step.
    private func binding(_ key: ReferenceWritableKeyPath<Prefs, Double>, step: Double) -> Binding<Double> {
        Binding(get: { prefs[keyPath: key] }, set: {
            let v = ($0 / step).rounded() * step
            guard v != prefs[keyPath: key] else { return }
            prefs[keyPath: key] = v
            prefs.objectWillChange.send()
        })
    }

    // MARK: actions

    /// A CommuteScout voice on the phone is picked like any other. One
    /// that is not plays its sample and offers the download; one already
    /// downloading or paused is picked and its download carries on.
    private func tap(_ v: VoiceCatalog.Voice, in pack: VoiceCatalog.Pack) {
        switch packs.state(pack.id) {
        case .installed:
            pick(v.id)
        case .downloading:
            pick(v.id, sample: v)
        case .paused, .failed, .none:
            previews.play(v)
            offer = v
        }
    }

    private func choose(_ v: VoiceCatalog.Voice, cellular: Bool) {
        guard let pack = neuralVoices.first(where: { $0.voice.id == v.id })?.pack else { return }
        if case let .noSpace(needed) = packs.problem(pack.id) {
            noSpace = "\(pack.title) need \(VoicePackFiles.label(needed)) free on this phone. Free up some space and try again."
            return
        }
        prefs.voiceId = v.id
        prefs.objectWillChange.send()
        Voice.refresh()
        packs.download(pack.id, cellular: cellular)
    }

    /// Picks a voice and says the sample in it. A CommuteScout voice
    /// still downloading plays its recorded sample instead.
    private func pick(_ id: String, sample clip: VoiceCatalog.Voice? = nil) {
        prefs.voiceId = id
        prefs.objectWillChange.send()
        Voice.refresh()
        previews.stop()
        if let clip { previews.play(clip) } else { play() }
    }

    /// Say the sample now. Outside a trip it cuts off the one before;
    /// during a trip it waits its turn behind the guidance.
    private func play() {
        previews.stop()
        model.alerts.preview(sample, interrupt: !model.state.isNavigating)
    }

    private func reload() {
        Voice.refresh()
        voices = Voice.installed
    }

    /// iOS 17 says when a voice is downloaded or deleted; earlier
    /// versions only get the reload when the app comes back to the front.
    private var voicesChanged: NotificationCenter.Publisher {
        if #available(iOS 17.0, *) {
            return NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)
        }
        return NotificationCenter.default.publisher(for: Notification.Name("cs.voice.never"))
    }
}

/// "Premium" or "Enhanced", as a small capsule beside a voice.
struct VoiceQualityBadge: View {
    let quality: VoiceOption.Quality

    private var tint: Color { quality == .premium ? .purple : .blue }

    var body: some View {
        Text(quality.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.15)))
    }
}
