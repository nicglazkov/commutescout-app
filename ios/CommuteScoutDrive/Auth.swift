import AuthenticationServices
import Combine
import CryptoKit
import FirebaseAuth
import FirebaseCore
import Foundation
import GoogleSignIn
import SwiftUI
import UIKit

/// The same account as the website: one Firebase user, signed in with
/// Google or Apple. The ID token goes to commutescout.com as a Bearer
/// header for reports, watches and account settings.
@MainActor
final class Account: NSObject, ObservableObject {
    @Published private(set) var user: User?
    @Published var busy = false
    @Published var error: String?

    private var listener: AuthStateDidChangeListenerHandle?
    private var nonce: String?
    private var appleContinuation: CheckedContinuation<ASAuthorization, Error>?

    override init() {
        super.init()
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        user = Auth.auth().currentUser
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, u in
            Task { @MainActor in self?.user = u }
        }
    }

    var signedIn: Bool { user != nil }
    var email: String? { user?.email }
    var displayName: String { user?.displayName ?? user?.email ?? "Signed in" }

    /// A fresh ID token for the server, or nil when signed out.
    func token() async -> String? {
        guard let user else { return nil }
        return try? await user.getIDToken()
    }

    // MARK: Google

    func signInWithGoogle() async {
        guard let root = Self.rootController else { return }
        busy = true; defer { busy = false }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)
            guard let idToken = result.user.idToken?.tokenString else { throw AccountError.noToken }
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
            try await Auth.auth().signIn(with: credential)
        } catch {
            if (error as NSError).code != GIDSignInError.canceled.rawValue { self.error = error.localizedDescription }
        }
    }

    // MARK: Apple

    func signInWithApple() async {
        busy = true; defer { busy = false }
        let raw = Self.randomNonce()
        nonce = raw
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email, .fullName]
        request.nonce = Self.sha256(raw)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        do {
            let auth: ASAuthorization = try await withCheckedThrowingContinuation { c in
                appleContinuation = c
                controller.performRequests()
            }
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken, let idToken = String(data: tokenData, encoding: .utf8) else {
                throw AccountError.noToken
            }
            let credential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: raw, fullName: cred.fullName)
            try await Auth.auth().signIn(with: credential)
        } catch {
            if (error as? ASAuthorizationError)?.code != .canceled { self.error = error.localizedDescription }
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
    }

    /// The website's "Delete account": the server removes watches, keys
    /// and the user record, then the Firebase user is deleted here.
    func deleteAccount() async -> Bool {
        guard let user, let token = await token() else { return false }
        busy = true; defer { busy = false }
        var req = URLRequest(url: Backend.base.appendingPathComponent("api/watch/account"))
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (_, resp) = try await Backend.session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else { throw AccountError.server }
            try await user.delete()
            GIDSignIn.sharedInstance.signOut()
            return true
        } catch {
            self.error = "Could not delete the account: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: helpers

    static var rootController: UIViewController? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }?.rootViewController
    }

    private static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var out = ""
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        for b in bytes { out.append(chars[Int(b) % chars.count]) }
        return out
    }

    private static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension Account: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    func authorizationController(controller _: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        appleContinuation?.resume(returning: authorization)
        appleContinuation = nil
    }

    func authorizationController(controller _: ASAuthorizationController, didCompleteWithError error: Error) {
        appleContinuation?.resume(throwing: error)
        appleContinuation = nil
    }

    func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        Self.rootController?.view.window ?? ASPresentationAnchor()
    }
}

enum AccountError: LocalizedError {
    case noToken, server
    var errorDescription: String? {
        switch self {
        case .noToken: "Sign-in did not return a token."
        case .server: "The server refused the request."
        }
    }
}

/// Signed-in requests to commutescout.com.
extension Backend {
    static func send(_ method: String, _ path: String, token: String, body: [String: Any]? = nil) async throws -> (Int, Data) {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await session.data(for: req)
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}

/// The sign-in sheet: Google or Apple, the same account as the website.
struct SignInSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let reason: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 44)).foregroundStyle(.tint)
                Text(reason).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal)
                Button {
                    Task { await model.account.signInWithApple(); if model.account.signedIn { dismiss() } }
                } label: {
                    Label("Continue with Apple", systemImage: "apple.logo").frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent).tint(.black)
                Button {
                    Task { await model.account.signInWithGoogle(); if model.account.signedIn { dismiss() } }
                } label: {
                    Label("Continue with Google", systemImage: "g.circle").frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                if model.account.busy { ProgressView() }
                Text("Same account as commutescout.com. Reports carry a pseudonym, never your name or email.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                Link("Privacy", destination: URL(string: "https://commutescout.com/privacy")!).font(.footnote)
                Spacer()
            }
            .padding(.top, 24).padding(.horizontal, 20)
            .navigationTitle("Sign in")
            .toolbar { Button("Cancel") { dismiss() } }
            .alert("Sign-in failed", isPresented: Binding(get: { model.account.error != nil }, set: { if !$0 { model.account.error = nil } })) {
                Button("OK") { model.account.error = nil }
            } message: { Text(model.account.error ?? "") }
        }
        .presentationDetents([.medium])
    }
}
