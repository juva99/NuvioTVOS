//
//  LoginView.swift
//  NuvioTV
//
//  Full-screen login gate shown before profile selection. Offers QR (TV) login
//  and email/password sign-in, plus "Continue without account". Ported from the
//  Android AuthQrSignInScreen / AuthSignInScreen.
//

import SwiftUI

struct LoginView: View {
    @ObservedObject var auth: AuthManager
    let onContinue: () -> Void

    enum Method: String, CaseIterable, Identifiable {
        case qr = "QR Code"
        case email = "Email"
        var id: String { rawValue }
    }

    @State private var method: Method = .qr
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var didTriggerContinue = false

    var body: some View {
        ZStack {
            Color.tvBackground.ignoresSafeArea()

            HStack(alignment: .center, spacing: 64) {
                leftPane
                    .frame(maxWidth: .infinity, alignment: .leading)
                rightPane
                    .frame(width: 760)
            }
            .padding(.horizontal, 120)
            .padding(.vertical, 80)
        }
        .onAppear {
            if auth.isAuthenticated {
                triggerContinue()
                return
            }
            if method == .qr { auth.startQrLogin() }
        }
        .onDisappear { auth.stopQrLogin() }
        .onChange(of: method) { newMethod in
            auth.errorMessage = nil
            if newMethod == .qr {
                auth.startQrLogin()
            } else {
                auth.stopQrLogin()
            }
        }
        .onChange(of: auth.authState) { state in
            if state.isAuthenticated { triggerContinue(delay: 0.9) }
        }
    }

    private func triggerContinue(delay: Double = 0) {
        guard !didTriggerContinue else { return }
        didTriggerContinue = true
        auth.stopQrLogin()
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { onContinue() }
        } else {
            onContinue()
        }
    }

    // MARK: - Left pane (branding)

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("NUVIO")
                .font(.system(size: 64, weight: .black))
                .foregroundColor(.white)

            Text(auth.isAuthenticated ? "You're signed in" : "Sign in to Nuvio")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.white)

            Text(auth.isAuthenticated
                 ? "Your account is connected on this TV. Your library, addons and progress will sync."
                 : "Scan a QR code with your phone or sign in with your email to sync your library, addons and watch progress.")
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(.white.opacity(0.6))
                .frame(maxWidth: 560, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let email = auth.currentEmail, !email.isEmpty {
                Text(email)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(Color(red: 0.49, green: 1.0, blue: 0.61))
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Right pane (login card)

    private var rightPane: some View {
        VStack(alignment: .center, spacing: 24) {
            if !auth.isAuthenticated {
                methodToggle
            }

            if auth.isAuthenticated {
                connectedContent
            } else if method == .qr {
                qrContent
            } else {
                emailContent
            }

            if let error = auth.errorMessage, !error.isEmpty {
                statusPill(error, isError: true)
            }

            if !auth.isBackendConfigured {
                statusPill("Backend not configured — add the Nuvio API URL and publishable key in AuthConfig.swift.", isError: false)
            }

            Divider().background(Color.white.opacity(0.1)).padding(.vertical, 4)

            LoginButton(title: "Continue without account", systemImage: "arrow.right") {
                auth.skipLogin()
                triggerContinue()
            }
        }
        .padding(40)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var methodToggle: some View {
        HStack(spacing: 12) {
            ForEach(Method.allCases) { m in
                MethodTab(title: m.rawValue, isSelected: method == m) {
                    if method != m { method = m }
                }
            }
        }
    }

    // MARK: QR content

    private var qrContent: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 280, height: 280)

                if let qr = auth.qrImage {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 248, height: 248)
                } else if auth.isBusy {
                    ProgressView()
                        .scaleEffect(1.3)
                        .tint(.black)
                } else {
                    Text("QR unavailable.\nRefresh to retry.")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.black.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }

            if let code = auth.qrCode, !code.isEmpty {
                Text("Code: \(code)")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }

            if let expires = auth.qrExpiresAt {
                CountdownText(target: expires)
            }

            if let status = auth.qrStatusMessage, !status.isEmpty, auth.errorMessage == nil {
                Text(status)
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.66))
                    .multilineTextAlignment(.center)
            }

            LoginButton(title: "Refresh QR", systemImage: "arrow.clockwise", disabled: auth.isBusy) {
                auth.startQrLogin()
            }
        }
    }

    // MARK: Email content

    private var emailContent: some View {
        VStack(spacing: 16) {
            Text(isSignUp ? "Create your account" : "Sign in with email")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .autocorrectionDisabled(true)
                .loginFieldStyle()

            SecureField("Password", text: $password)
                .textContentType(isSignUp ? .newPassword : .password)
                .loginFieldStyle()

            LoginButton(
                title: isSignUp ? "Create Account" : "Sign In",
                systemImage: "envelope.fill",
                prominent: true,
                disabled: auth.isBusy || email.isEmpty || password.isEmpty
            ) {
                Task {
                    if isSignUp {
                        await auth.signUp(email: email, password: password)
                    } else {
                        await auth.signIn(email: email, password: password)
                    }
                }
            }

            Button(action: { isSignUp.toggle(); auth.errorMessage = nil }) {
                Text(isSignUp ? "Already have an account? Sign in" : "New to Nuvio? Create an account")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Connected content

    private var connectedContent: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(Color(red: 0.49, green: 1.0, blue: 0.61))
            Text(auth.qrStatusMessage ?? "Signed in successfully")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
            ProgressView().tint(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func statusPill(_ text: String, isError: Bool) -> some View {
        Text(text)
            .font(.system(size: 19, weight: .medium))
            .foregroundColor(isError ? Color(red: 1.0, green: 0.43, blue: 0.43) : .white.opacity(0.7))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background((isError ? Color.red.opacity(0.18) : Color.white.opacity(0.06)))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Components

private struct MethodTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(isSelected || focused ? .black : .white)
                .padding(.horizontal, 28)
                .frame(height: 52)
                .background(isSelected || focused ? Color.white : Color.white.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(PosterCardButtonStyle())
        .focused($focused)
        .focusEffectDisabledIfAvailable()
        .scaleEffect(focused ? 1.05 : 1)
        .animation(.easeOut(duration: 0.12), value: focused)
    }
}

private struct LoginButton: View {
    let title: String
    var systemImage: String? = nil
    var prominent: Bool = false
    var disabled: Bool = false
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(foreground)
            .padding(.horizontal, 26)
            .frame(height: 58)
            .frame(maxWidth: .infinity)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(disabled ? 0.5 : 1)
            .scaleEffect(focused && !disabled ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .focused($focused)
        .focusEffectDisabledIfAvailable()
        .animation(.easeOut(duration: 0.12), value: focused)
    }

    private var foreground: Color {
        if focused { return .black }
        return prominent ? .black : .white
    }

    private var background: Color {
        if focused { return .white }
        return prominent ? Color.white.opacity(0.92) : Color.white.opacity(0.12)
    }
}

/// Live "Expires in mm:ss" countdown.
private struct CountdownText: View {
    let target: Date

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            let remaining = max(0, Int(target.timeIntervalSince(context.date)))
            Text(String(format: "Expires in %02d:%02d", remaining / 60, remaining % 60))
                .font(.system(size: 19))
                .foregroundColor(.white.opacity(0.55))
        }
    }
}

private extension View {
    func loginFieldStyle() -> some View {
        self
            .font(.system(size: 22))
            .textFieldStyle(.plain)
            .padding(.horizontal, 20)
            .frame(height: 60)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
