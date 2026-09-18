import FirebaseCore
import FirebaseMessaging
import UIKit
import UserNotifications

/// Watch alerts and alerts ahead reach the phone through APNs by way of
/// Firebase Cloud Messaging. The device token is registered with the
/// account on sign-in and whenever Firebase rotates it, and forgotten on
/// sign-out, so a shared phone never keeps getting the previous
/// account's alerts.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    /// Set by the registrar: called with every fresh FCM token.
    static var onToken: ((String) -> Void)?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        DriveLog.note("push: APNs registration failed: " + error.localizedDescription)
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Self.onToken?(fcmToken)
    }

    /// Alerts show even while the app is in front.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

@MainActor
final class PushRegistrar {
    private let account: Account
    private let tokenKey = "cs.fcm"
    private let registeredKey = "cs.fcm.registered"

    init(account: Account) {
        self.account = account
        AppDelegate.onToken = { [weak self] t in
            Task { @MainActor in await self?.register(t) }
        }
    }

    /// Asked once the person signs in: alerts need permission to show.
    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let ok = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            DriveLog.note("push: permission " + (ok ? "granted" : "declined"))
        }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// The current token goes to the signed-in account.
    func register(_ fresh: String? = nil) async {
        if let fresh { UserDefaults.standard.set(fresh, forKey: tokenKey) }
        guard let token = UserDefaults.standard.string(forKey: tokenKey), let auth = await account.token() else { return }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard let (status, _) = try? await Backend.send("POST", "api/me/devices", token: auth,
                                                        body: ["platform": "ios", "token": token, "app_version": version])
        else { return }
        if status == 200 {
            UserDefaults.standard.set(token, forKey: registeredKey)
            DriveLog.note("push: registered with the account")
        } else {
            DriveLog.note("push: register failed " + String(status))
        }
    }

    /// Before sign-out: the account forgets this phone.
    func forget() async {
        guard let token = UserDefaults.standard.string(forKey: registeredKey), let auth = await account.token() else { return }
        _ = try? await Backend.send("DELETE", "api/me/devices", token: auth, body: ["platform": "ios", "token": token])
        UserDefaults.standard.removeObject(forKey: registeredKey)
    }
}
