import AVFoundation
import SwiftUI

/// Settings > Voice: who says the turns and the alerts, how fast and at
/// what pitch. Every voice here is one iOS keeps on the phone, so all
/// of them are free and work with no signal. Tapping a voice picks it
/// and says a sample sentence in it; the speed and pitch sliders say
/// the sample again when let go.
struct VoiceSettings: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var voices: [VoiceOption] = []
    @State private var allAccents = false

    private var prefs: Prefs { model.prefs }

    /// English voices worth offering, best first.
    private var offered: [VoiceOption] { VoicePick.offered(voices, language: Voice.language) }
    private var region: String? { Voice.region?.uppercased() }
    private func isLocal(_ v: VoiceOption) -> Bool { VoicePick.regionCode(v.language) == region }

    /// The list: voices with the phone's own accent unless all are asked
    /// for, and the voice in use whatever its accent. With no voice for
    /// the region at all, every accent.
    private var shown: [VoiceOption] {
        if allAccents || !offered.contains(where: isLocal) { return offered }
        return offered.filter { isLocal($0) || $0.id == speaking?.id }
    }
    private var hasOtherAccents: Bool { offered.contains(where: isLocal) && offered.contains { !isLocal($0) } }

    private var speaking: VoiceOption? { Voice.resolve(saved: prefs.voiceId, among: voices) }
    private var best: VoiceOption? { VoicePick.best(offered, region: region, systemDefault: Voice.systemDefault) }
    /// Automatic: nothing picked, or the pick was deleted from the phone.
    private var automatic: Bool { !offered.contains { $0.id == prefs.voiceId } }

    /// What a drive sounds like, in the driver's units.
    private var sample: String { "In \(Units.spoken(805)), turn right onto Main Street. Police reported ahead." }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    SettingsIcon(symbol: "waveform", color: .pink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(speaking?.name ?? "System voice").font(.headline)
                        Text(speaking.map(detail) ?? "English").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if let q = speaking?.quality, q > .standard { VoiceQualityBadge(quality: q) }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                Button { play() } label: { Label("Test voice", systemImage: "play.circle.fill") }
                    .accessibilityIdentifier("voice-test")
            } footer: { Text("Turn instructions and road alerts are both spoken in this voice.") }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Speed", value: percent(prefs.voiceRate, of: Voice.defaultRate))
                    Slider(value: binding(\.voiceRate, step: 0.01), in: Voice.rateRange) { Text("Speed") }
                        minimumValueLabel: { Image(systemName: "tortoise.fill").foregroundStyle(.secondary) }
                        maximumValueLabel: { Image(systemName: "hare.fill").foregroundStyle(.secondary) }
                        onEditingChanged: { if !$0 { play() } }
                        .accessibilityIdentifier("voice-speed")
                }
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Pitch", value: percent(prefs.voicePitch, of: Voice.defaultPitch))
                    Slider(value: binding(\.voicePitch, step: 0.05), in: Voice.pitchRange) { Text("Pitch") }
                        minimumValueLabel: { Text("Low").font(.caption).foregroundStyle(.secondary) }
                        maximumValueLabel: { Text("High").font(.caption).foregroundStyle(.secondary) }
                        onEditingChanged: { if !$0 { play() } }
                        .accessibilityIdentifier("voice-pitch")
                }
                Button("Reset speed and pitch") {
                    prefs.voiceRate = Voice.defaultRate
                    prefs.voicePitch = Voice.defaultPitch
                    prefs.objectWillChange.send()
                }
                .disabled(prefs.voiceRate == Voice.defaultRate && prefs.voicePitch == Voice.defaultPitch)
                .accessibilityIdentifier("voice-reset")
            } header: { Text("Speed and pitch") }

            Section {
                Button { pick("") } label: {
                    choiceLabel("Automatic",
                                best.map { "Best on this phone: \($0.name), \($0.quality.label)" } ?? "The system voice",
                                quality: nil, selected: automatic)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(automatic ? .isSelected : [])
                .accessibilityIdentifier("voice-automatic")
                if hasOtherAccents {
                    Toggle("Show all English accents", isOn: $allAccents)
                        .accessibilityIdentifier("voice-all-accents")
                }
            } header: { Text("Voice") } footer: {
                Text("Automatic picks the best voice on this phone for your region, and moves to a better one when you download it. Tap a voice to hear it.")
            }

            ForEach([VoiceOption.Quality.premium, .enhanced, .standard], id: \.self) { q in
                let group = shown.filter { $0.quality == q }
                if !group.isEmpty {
                    Section {
                        ForEach(group) { v in
                            Button { pick(v.id) } label: {
                                choiceLabel(v.name, detail(v), quality: v.quality, selected: !automatic && prefs.voiceId == v.id)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(!automatic && prefs.voiceId == v.id ? .isSelected : [])
                            .accessibilityIdentifier("voice-\(v.id)")
                        }
                    } header: { Text(q.label) }
                }
            }

            Section {
                if offered.isEmpty {
                    Text("No English voice is on this phone yet.").foregroundStyle(.secondary)
                }
            } header: { Text("More voices") } footer: {
                Text("More natural voices are free to download. In the Settings app, go to Accessibility > Read & Speak > Voices > English, choose a voice, and download its Enhanced or Premium version. On iOS 18 and earlier, Read & Speak is called Spoken Content. When you come back, the new voice is in this list.")
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { reload() }
        }
        .onReceive(voicesChanged) { _ in reload() }
    }

    private func choiceLabel(_ title: String, _ subtitle: String, quality: VoiceOption.Quality?, selected: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            if let quality, quality > .standard { VoiceQualityBadge(quality: quality) }
            Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color.accentColor)
                .opacity(selected ? 1 : 0)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    /// "English (UK), female".
    private func detail(_ v: VoiceOption) -> String {
        [v.accent, v.gender?.lowercased()].compactMap { $0 }.joined(separator: ", ")
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

    private func pick(_ id: String) {
        prefs.voiceId = id
        prefs.objectWillChange.send()
        play()
    }

    /// Say the sample now. Outside a trip it cuts off the one before;
    /// during a trip it waits its turn behind the guidance.
    private func play() {
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
