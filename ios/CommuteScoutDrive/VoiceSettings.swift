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
    @StateObject private var sampler = VoiceSampler()
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
    private var sample: String { "In \(Units.spoken(805)), crash in the right lane. Move one lane left." }

    var body: some View {
        dialogs(form)
            .onAppear {
                reload()
                // Ready the sample in the voice in use, so Test voice speaks at once.
                if Voice.neural != nil, !model.state.isNavigating { NeuralVoices.shared.prerender([(sample, -1)]) }
            }
            .onDisappear { previews.stop(); sampler.stop() }
            .onChange(of: scenePhase) { phase in
                if phase == .active { reload() }
            }
            .onReceive(voicesChanged) { _ in reload() }
    }

    private var form: some View {
        DGPage(title: "Voice", identifier: "page-voice") {
            DGGroup {
                DGSwitchRow(title: "Speak directions and alerts",
                            sub: "Turn this off to mute every voice. Alerts still show on screen.",
                            isOn: Binding(get: { !model.muted }, set: { _ in model.toggleMute() }),
                            identifier: "voice-speak") {
                    DGTile(symbol: "speaker.wave.2.fill", color: DG.hex(0x2f7cf6))
                }
            }
            .padding(.top, 8)
            voiceSection
            speedSection
            VoicePackSection(previews: previews, picked: prefs.voiceId) { pick($0) }
        }
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
        VStack(alignment: .leading, spacing: 0) {
            DGSectionLabel("Voices on this phone", trailing: AnyView(DGTag(text: "Free, works offline")))
            DGGroup {
                row("Automatic", automaticDetail, selected: automatic, id: "voice-automatic") { pick("") }
                ForEach(neuralVoices.filter { show($0.voice.accent, $0.voice.id) }, id: \.voice.id) { item in
                    DGDivider(inset: 44)
                    neuralRow(item.voice, in: item.pack)
                }
                ForEach(offered.filter { show($0.language, $0.id) }) { v in
                    DGDivider(inset: 44)
                    row(v.name, detail(v), quality: v.quality, selected: !automatic && prefs.voiceId == v.id, id: "voice-\(v.id)",
                        play: { previews.stop(); sampler.play(sample, voice: v.id) }) { pick(v.id) }
                }
                if hasOtherAccents {
                    DGDivider(inset: 14)
                    DGSwitchRow(title: "Show all English accents", isOn: $allAccents, identifier: "voice-all-accents")
                }
            }
            DGFootnote("These voices are built into your phone and cost nothing. Add more in your phone's Spoken content settings. CommuteScout voices are computer-generated and need no signal once downloaded.")
        }
    }

    private func slider(_ title: String, _ value: String, @ViewBuilder _ control: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(DG.font(16, .medium)).foregroundStyle(DG.ink)
                Spacer()
                Text(value).font(DG.font(15)).foregroundStyle(DG.sub)
            }
            control().tint(DG.path)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DGSectionLabel("Speed and pitch")
            DGGroup {
                slider("Speed", percent(prefs.voiceRate, of: Voice.defaultRate)) {
                    Slider(value: binding(\.voiceRate, step: 0.01), in: Voice.rateRange) { Text("Speed") }
                        minimumValueLabel: { Image(systemName: "tortoise.fill").foregroundStyle(DG.faint) }
                        maximumValueLabel: { Image(systemName: "hare.fill").foregroundStyle(DG.faint) }
                        onEditingChanged: { if !$0 { play() } }
                        .accessibilityIdentifier("voice-speed")
                }
                if neural == nil {
                    DGDivider(inset: 14)
                    slider("Pitch", percent(prefs.voicePitch, of: Voice.defaultPitch)) {
                        Slider(value: binding(\.voicePitch, step: 0.05), in: Voice.pitchRange) { Text("Pitch") }
                            minimumValueLabel: { Text("Low").font(DG.font(12)).foregroundStyle(DG.faint) }
                            maximumValueLabel: { Text("High").font(DG.font(12)).foregroundStyle(DG.faint) }
                            onEditingChanged: { if !$0 { play() } }
                            .accessibilityIdentifier("voice-pitch")
                    }
                }
                DGDivider(inset: 14)
                HStack(spacing: 10) {
                    Button { play() } label: { Label("Test voice", systemImage: "play.fill") }
                        .buttonStyle(DGButtonStyle(kind: .tinted(.low), height: 40))
                        .accessibilityIdentifier("voice-test")
                    Button("Reset to normal") {
                        prefs.voiceRate = Voice.defaultRate
                        prefs.voicePitch = Voice.defaultPitch
                        prefs.objectWillChange.send()
                    }
                    .buttonStyle(DGButtonStyle(kind: .glass, height: 40))
                    .disabled(prefs.voiceRate == Voice.defaultRate && prefs.voicePitch == Voice.defaultPitch)
                    .accessibilityIdentifier("voice-reset")
                }
                .padding(14)
            }
            DGFootnote(speakingNote)
        }
    }

    // MARK: rows

    /// A voice: the check, its name and accent, and a round play button
    /// that plays the sample without picking it. A tap on the row picks
    /// the voice and plays it.
    private func row(_ title: String, _ subtitle: String, quality: VoiceOption.Quality? = nil, status: String? = nil,
                     selected: Bool, id: String, play: (() -> Void)? = nil, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(DG.path)
                        .frame(width: 24).opacity(selected ? 1 : 0)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(title).font(DG.font(16, .medium)).foregroundStyle(DG.ink)
                            if let quality, quality > .standard {
                                Text(quality.label).font(DG.font(12, .semibold)).foregroundStyle(DG.sub)
                            }
                        }
                        Text(subtitle).font(DG.T.rowSub).foregroundStyle(DG.sub).lineLimit(2)
                        if let status { Text(status).font(DG.font(13, .medium)).foregroundStyle(DG.path).monospacedDigit() }
                    }
                    Spacer(minLength: 8)
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier(id)
            if let play {
                Button(action: play) {
                    Image(systemName: "play.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(DG.inkColor(.low))
                        .frame(width: 42, height: 42).background(DG.path.opacity(0.1), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(DGPressStyle())
                .accessibilityLabel("Play \(title)")
                .accessibilityIdentifier("play-" + id)
            }
        }
        .padding(.leading, 10).padding(.trailing, 12).frame(minHeight: 60)
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
        return row(v.name, subtitle, status: status, selected: prefs.voiceId == v.id, id: "voice-\(v.id)",
                   play: { sampler.stop(); previews.play(v) }) { tap(v, in: pack) }
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
        sampler.stop()
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

/// Plays the sample in one system voice without picking it, at the
/// driver's speed and pitch, so voices can be compared down the list.
@MainActor
final class VoiceSampler: ObservableObject {
    private let synth = AVSpeechSynthesizer()

    func play(_ text: String, voice id: String) {
        stop()
        let u = Voice.utterance(text)
        u.voice = AVSpeechSynthesisVoice(identifier: id) ?? u.voice
        synth.speak(u)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }
}

/// "Premium" or "Enhanced", as a small capsule beside a voice.
struct VoiceQualityBadge: View {
    let quality: VoiceOption.Quality

    private var tint: Color { quality == .premium ? .purple : .blue }

    var body: some View {
        Text(quality.label)
            .font(DG.font(11, .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.15)))
    }
}
