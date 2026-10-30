import CoreLocation
import SwiftUI
import UserNotifications

/// The first run, over the live map: three steps, each one ask. Location
/// while the app is in use, notifications for watch areas, and an
/// optional sign-in. Shown once; an install that was set up before it
/// existed skips it, and so do test runs.
struct WelcomeOverlay: View {
    @EnvironmentObject var model: AppModel
    var finish: () -> Void
    @State private var step: WelcomeStep = .location
    @State private var showSignIn = false
    @State private var asker = LocationAsker()

    var body: some View {
        ZStack {
            // The chrome under it is out of reach until the run is done;
            // the map still shows.
            LinearGradient(colors: [DG.background.opacity(0.9), DG.background.opacity(0), DG.background.opacity(0), DG.background.opacity(0.7)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .contentShape(Rectangle())
            VStack(spacing: 12) {
                brand
                if step == .notifications {
                    sampleNote.transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
                card
            }
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("welcome")
        .sheet(isPresented: $showSignIn, onDismiss: { if model.account.signedIn { done() } }) {
            SignInSheet(reason: "Sign in to report, keep watch areas and manage API keys.")
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            DGIconView(name: "nav", size: 17, stroke: 2.2).foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(LinearGradient(colors: [DG.hex(0x4a8ff8), DG.path], startPoint: .top, endPoint: .bottom), in: Circle())
            Text("CommuteScout").font(DG.font(17, .bold)).foregroundStyle(DG.ink)
        }
        .padding(.leading, 8).padding(.trailing, 18).frame(height: 50)
        .dgGlass(Capsule())
    }

    private var sampleNote: some View {
        HStack(spacing: 12) {
            DGDisc(kind: .crash, tone: .high, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("Home area: crash on US-101").font(DG.font(15, .semibold)).foregroundStyle(DG.ink)
                Text("Right lane blocked at University Ave").font(DG.font(13)).foregroundStyle(DG.sub)
            }
            Spacer(minLength: 4)
            Text("now").font(DG.font(12)).foregroundStyle(DG.faint).frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(12).fixedSize(horizontal: false, vertical: true)
        .dgGlass(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(WelcomeStep.allCases, id: \.rawValue) { s in
                    Capsule().fill(s.rawValue <= step.rawValue ? DG.path : DG.ink.opacity(0.1)).frame(height: 4)
                }
                Text(step.progress).font(DG.font(13, .semibold)).foregroundStyle(DG.sub).fixedSize().padding(.leading, 6)
            }
            Text(step.title).font(DG.font(24, .bold)).foregroundStyle(DG.ink)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 18)
            Text(step.body).font(DG.font(16)).foregroundStyle(DG.sub)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            Group {
                switch step {
                case .location:
                    ask("location.fill", "Use your location while you use the app", "To show what is ahead on your route. It is never shared or sold.")
                case .notifications:
                    ask("bell.fill", "Allow notifications", "Only for watch areas and trips you start. You can change this anytime.")
                case .account:
                    perks
                }
            }
            .padding(.top, 16)
            HStack(spacing: 10) {
                Button(primaryLabel) { primary() }
                    .buttonStyle(.dgPrimary)
                    .accessibilityIdentifier("welcome-primary")
                Button(step == .account ? "Start driving" : "Not now") { next() }
                    .buttonStyle(DGButtonStyle(kind: .glass))
                    .frame(maxWidth: 140)
                    .accessibilityIdentifier("welcome-skip")
            }
            .padding(.top, 16)
        }
        .padding(20)
        .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: DG.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DG.R.card, style: .continuous).strokeBorder(DG.hair, lineWidth: 1))
        .shadow(color: DG.ink.opacity(0.14), radius: 24, y: 8)
        .animation(DG.spring, value: step)
    }

    private var primaryLabel: String {
        switch step { case .location: "Allow while using"; case .notifications: "Allow notifications"; case .account: "Sign in" }
    }

    private func ask(_ symbol: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(LinearGradient(colors: [DG.hex(0x4a8ff8), DG.path], startPoint: .top, endPoint: .bottom), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DG.font(15, .semibold)).foregroundStyle(DG.ink)
                Text(sub).font(DG.font(13)).foregroundStyle(DG.ink.opacity(0.7))
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(DG.path.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DG.path.opacity(0.14), lineWidth: 1))
    }

    private var perks: some View {
        let items: [(String, String)] = [("Reports from the road", "exclamationmark.bubble"), ("Watch areas everywhere", "eye"),
                                         ("Plugins", "puzzlepiece.extension"), ("API keys", "key")]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.1).font(.system(size: 15, weight: .semibold)).foregroundStyle(DG.path).frame(width: 20)
                    Text(item.0).font(DG.font(14, .semibold)).foregroundStyle(DG.ink).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).frame(minHeight: 52)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(DG.hair, lineWidth: 1))
            }
        }
    }

    private func primary() {
        switch step {
        case .location:
            asker.ask()
            next()
        case .notifications:
            Task {
                let center = UNUserNotificationCenter.current()
                if await center.notificationSettings().authorizationStatus == .notDetermined {
                    _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
                }
                UIApplication.shared.registerForRemoteNotifications()
                next()
            }
        case .account:
            showSignIn = true
        }
    }

    private func next() {
        if let n = WelcomeStep(rawValue: step.rawValue + 1) {
            withAnimation(DG.spring) { step = n }
        } else {
            done()
        }
    }

    private func done() {
        model.prefs.welcomeDone = true
        finish()
    }
}

/// Asks for location while in use, once, if it was never asked.
private final class LocationAsker {
    private let manager = CLLocationManager()
    func ask() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
    }
}
