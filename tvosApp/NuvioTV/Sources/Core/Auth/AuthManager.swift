//
//  AuthManager.swift
//  NuvioTV
//
//  Observable orchestrator for the account system: global auth state, session
//  persistence, email sign-in/up, and the QR (TV) login start/poll/exchange
//  loop. Mirrors the Android AccountViewModel + AuthManager split.
//

import SwiftUI
import UIKit

@MainActor
final class AuthManager: ObservableObject {
    // Global auth state.
    @Published private(set) var authState: AuthState = .loading

    // QR login UI state.
    @Published var qrImage: UIImage?
    @Published var qrCode: String?
    @Published var qrStatusMessage: String?
    @Published var qrExpiresAt: Date?

    // Shared.
    @Published var isBusy = false
    @Published var errorMessage: String?

    private let service = AuthService()
    private let store = SessionStore()

    private var qrNonce: String?
    private var qrAnonAccessToken: String?
    private var pollTask: Task<Void, Never>?

    var isAuthenticated: Bool { authState.isAuthenticated }
    var isBackendConfigured: Bool { AuthConfig.isConfigured }

    var currentEmail: String? {
        if case let .fullAccount(_, email) = authState { return email }
        return nil
    }

    /// Whether the login gate should be shown on launch (not signed in and the
    /// user hasn't previously chosen to continue without an account).
    var shouldShowLoginGate: Bool {
        !isAuthenticated && !store.didSkipLogin
    }

    init() {
        restoreSession()
    }

    // MARK: - Session restore / persistence

    private func restoreSession() {
        guard let session = store.load() else {
            authState = .signedOut
            return
        }
        authState = .fullAccount(userId: session.userId, email: session.email ?? "")
        if session.isExpired {
            Task { await self.refreshIfPossible(session) }
        }
    }

    private func refreshIfPossible(_ session: AuthSession) async {
        if let refreshed = try? await service.refresh(refreshToken: session.refreshToken) {
            apply(session: refreshed)
        }
    }

    private func apply(session: AuthSession) {
        store.save(session)
        authState = .fullAccount(userId: session.userId, email: session.email ?? "")
    }

    // MARK: - Skip / sign out

    func skipLogin() {
        store.didSkipLogin = true
    }

    func signOut() {
        pollTask?.cancel()
        store.clear()
        clearQrState()
        authState = .signedOut
    }

    // MARK: - Email

    func signIn(email: String, password: String) async {
        await runEmail { try await self.service.signInWithEmail(email: email, password: password) }
    }

    func signUp(email: String, password: String) async {
        await runEmail { try await self.service.signUpWithEmail(email: email, password: password) }
    }

    private func runEmail(_ op: @escaping () async throws -> AuthSession) async {
        guard ensureConfigured() else { return }
        isBusy = true
        errorMessage = nil
        do {
            apply(session: try await op())
        } catch {
            errorMessage = friendly(error)
        }
        isBusy = false
    }

    // MARK: - QR login

    func startQrLogin() {
        guard ensureConfigured() else { return }
        pollTask?.cancel()
        clearQrState()
        isBusy = true
        errorMessage = nil
        qrStatusMessage = "Preparing QR login…"

        let nonce = Self.makeNonce()
        qrNonce = nonce

        Task {
            do {
                let anon = try await service.signInAnonymously()
                qrAnonAccessToken = anon.accessToken
                let start = try await service.startTvLoginSession(
                    accessToken: anon.accessToken,
                    deviceNonce: nonce,
                    deviceName: Self.deviceName
                )
                qrCode = start.code
                qrImage = QRCode.image(from: start.webUrl)
                qrExpiresAt = Self.parseDate(start.expiresAt)
                qrStatusMessage = "Scan QR, approve in browser, then return here."
                isBusy = false
                startPolling(intervalSeconds: max(start.pollIntervalSeconds, 2))
            } catch {
                errorMessage = friendly(error)
                qrStatusMessage = "Failed to start QR login"
                isBusy = false
            }
        }
    }

    func stopQrLogin() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func startPolling(intervalSeconds: Int) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var interval = intervalSeconds
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                if Task.isCancelled { return }
                guard let self else { return }
                interval = await self.pollOnce(currentInterval: interval)
            }
        }
    }

    /// Runs a single poll; returns the (possibly updated) poll interval.
    private func pollOnce(currentInterval: Int) async -> Int {
        guard let code = qrCode, let nonce = qrNonce, let anon = qrAnonAccessToken else {
            return currentInterval
        }
        do {
            let result = try await service.pollTvLoginSession(accessToken: anon, code: code, deviceNonce: nonce)
            var interval = currentInterval
            if let secs = result.pollIntervalSeconds { interval = max(secs, 2) }
            if let exp = result.expiresAt.flatMap(Self.parseDate) { qrExpiresAt = exp }

            switch result.status.lowercased() {
            case "approved":
                qrStatusMessage = "Login approved. Finishing sign in…"
                pollTask?.cancel()
                await exchange(code: code, nonce: nonce, anon: anon)
            case "pending":
                qrStatusMessage = "Waiting for approval on your phone…"
            case "expired", "used", "cancelled":
                qrStatusMessage = "QR login expired. Generate a new code."
                pollTask?.cancel()
            default:
                qrStatusMessage = "Status: \(result.status)"
            }
            return interval
        } catch {
            errorMessage = friendly(error)
            return currentInterval
        }
    }

    private func exchange(code: String, nonce: String, anon: String) async {
        isBusy = true
        do {
            let session = try await service.exchangeTvLoginSession(accessToken: anon, code: code, deviceNonce: nonce)
            apply(session: session)
            qrStatusMessage = "Signed in successfully"
            clearQrState()
        } catch {
            errorMessage = friendly(error)
            qrStatusMessage = "Could not complete QR sign in"
        }
        isBusy = false
    }

    private func clearQrState() {
        qrImage = nil
        qrCode = nil
        qrExpiresAt = nil
        qrNonce = nil
        qrAnonAccessToken = nil
    }

    // MARK: - Helpers

    @discardableResult
    private func ensureConfigured() -> Bool {
        if AuthConfig.isConfigured { return true }
        errorMessage = "Account backend isn't configured yet. Add your Supabase URL and anon key in AuthConfig.swift."
        return false
    }

    private func friendly(_ error: Error) -> String {
        (error as? AuthError)?.message ?? error.localizedDescription
    }

    private static var deviceName: String {
        UIDevice.current.name
    }

    private static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func parseDate(_ s: String) -> Date? {
        if let d = isoFormatter.date(from: s) { return d }
        return ISO8601DateFormatter().date(from: s)
    }
}

/// UserDefaults-backed session persistence. Tokens would ideally live in the
/// Keychain; UserDefaults matches the rest of this prototype's storage and is
/// isolated here so it can be swapped later.
private struct SessionStore {
    private let sessionKey = "nuvio.auth.session"
    private let skipKey = "nuvio.auth.skippedLogin"
    private let defaults = UserDefaults.standard

    func load() -> AuthSession? {
        guard let data = defaults.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func save(_ session: AuthSession) {
        if let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: sessionKey)
        }
        didSkipLogin = false
    }

    func clear() { defaults.removeObject(forKey: sessionKey) }

    var didSkipLogin: Bool {
        get { defaults.bool(forKey: skipKey) }
        nonmutating set { defaults.set(newValue, forKey: skipKey) }
    }
}
