import AuthenticationServices
import CryptoKit
import SwiftUI

/// You › Account. An account is only for Coach, photo estimates and AI Chef; the log
/// stays on this iPhone. Sign in with Apple (when the capability is on) or a
/// one-time code by email. Signed in: who, Sign out, Delete account.
struct AccountView: View {
    @Environment(AccountStore.self) private var account
    @Environment(LocalStore.self) private var store
    @Environment(AIConsentStore.self) private var consent
    @Environment(ReminderService.self) private var reminders
    @Environment(\.vessHaptics) private var haptics

    @State private var confirmDelete = false
    @State private var isWorking = false
    @State private var error: BackendError?

    var body: some View {
        ProfilePage(title: "Account") {
            // One headline, signed in or not.
            ProfileIntro(
                title: "An account for AI features.",
                text: "Only for Coach, photo estimates and AI Chef. Your log stays on this iPhone."
            )
            if let session = account.session {
                signedIn(session)
            } else {
                AccountSignInForm()
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .vessKeyboardDoneButton()
    }

    // MARK: Signed in

    @ViewBuilder
    private func signedIn(_ session: AuthSession) -> some View {
        VESSRowGroup {
            VESSListRow(
                systemImage: session.provider == "apple" ? "apple.logo" : "envelope",
                title: Text(session.provider == "apple" ? "Sign in with Apple" : "Email"),
                subtitle: session.email.map { Text(verbatim: $0) },
                showsChevron: false
            )
            .accessibilityIdentifier("account.identity")
        }
        .vessHairlineBottom()

        if let error {
            AccountErrorText(error: error)
        }

        VStack(spacing: VESSSpacing.sm) {
            Button("Sign out") {
                Task { await account.signOut() }
            }
            .buttonStyle(.vessSecondary)
            .accessibilityIdentifier("account.signOut")

            Button("Delete account", role: .destructive) { confirmDelete = true }
                .buttonStyle(.vessSecondary)
                .foregroundStyle(VESSColor.criticalText)
                .disabled(isWorking)
                .accessibilityIdentifier("account.delete")
                .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete account", role: .destructive) { delete(alsoLocalData: false) }
                    Button("Delete account and all data", role: .destructive) { delete(alsoLocalData: true) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Coach, photo estimates and AI Chef stop until you sign in again. Your log stays on this iPhone unless you also delete all data.")
                }
        }
    }

    private func delete(alsoLocalData: Bool) {
        isWorking = true
        error = nil
        Task {
            do {
                try await account.deleteAccount()
                if alsoLocalData { try LocalDataWipe.run(store: store, consent: consent, reminders: reminders) }
                haptics.play(.warning)
            } catch {
                self.error = BackendError.from(error)
            }
            isWorking = false
        }
    }
}

/// Sign in with Apple (when the capability is on) and the email code. Also
/// used where Coach or photos ask for an account.
struct AccountSignInForm: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum Step: Equatable { case email, code(String) }

    @State private var step: Step = .email
    @State private var email = ""
    @State private var code = ""
    @State private var isWorking = false
    @State private var error: BackendError?
    @State private var rawNonce = ""

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.lg) {
            if !account.isConfigured {
                AccountErrorText(error: .notConfigured)
            } else {
                if account.appleSignInEnabled {
                    SignInWithAppleButton(.signIn, onRequest: prepare, onCompletion: complete)
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: VESSHitTarget.control)
                        .clipShape(Capsule())
                        .accessibilityIdentifier("account.apple")
                    Text("or with a code by email")
                        .vessTextStyle(.labelCaps)
                        .foregroundStyle(VESSColor.tertiaryText)
                        .frame(maxWidth: .infinity)
                }
                switch step {
                case .email: emailStep
                case .code(let address): codeStep(address)
                }
                if let error { AccountErrorText(error: error) }
            }
        }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSTextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .onSubmit(sendCode)
                .accessibilityIdentifier("account.email")
            Button(action: sendCode) {
                Text(isWorking ? "Sending…" : "Send code")
            }
            .buttonStyle(account.appleSignInEnabled ? .vessSecondary : .vessPrimary)
            .disabled(!isValidEmail || isWorking)
            .accessibilityIdentifier("account.sendCode")
        }
    }

    private func codeStep(_ address: String) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            Text("We sent a 6-digit code to \(Text(verbatim: address)).")
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            VESSTextField("Code", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .accessibilityIdentifier("account.code")
                // Pasted or autofilled codes keep only their 6 digits; a new
                // try clears the last message.
                .onChange(of: code) { _, new in
                    let normalized = EmailCode.normalized(new)
                    if normalized != new { code = normalized }
                    error = nil
                }
            Button(action: verify) {
                Text(isWorking ? "Checking…" : "Sign in")
            }
            .buttonStyle(.vessPrimary)
            .disabled(!EmailCode.isComplete(code) || isWorking)
            .accessibilityIdentifier("account.verify")
            // Side by side; stacked at accessibility sizes.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: VESSSpacing.sm))
                : AnyLayout(HStackLayout())
            layout {
                Button("Use another email") {
                    step = .email
                    code = ""
                    error = nil
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Button("Send again", action: sendCode)
                    .disabled(isWorking)
            }
            .buttonStyle(.vessQuiet)
        }
    }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isValidEmail: Bool {
        let parts = trimmedEmail.split(separator: "@")
        return trimmedEmail.count <= InputLimits.email && parts.count == 2 && parts[1].contains(".") && !parts[0].isEmpty
    }

    private func sendCode() {
        guard isValidEmail, !isWorking else { return }
        run {
            try await account.requestEmailCode(trimmedEmail)
            step = .code(trimmedEmail)
        }
    }

    private func verify() {
        guard case .code(let address) = step, EmailCode.isComplete(code) else { return }
        run { try await account.verifyEmailCode(code, email: address) }
    }

    // MARK: Sign in with Apple

    /// A fresh random nonce per request; Apple gets its SHA-256, GoTrue the raw one.
    private func prepare(_ request: ASAuthorizationAppleIDRequest) {
        rawNonce = Self.randomNonce()
        request.requestedScopes = [.email]
        request.nonce = SHA256.hash(data: Data(rawNonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func complete(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8)
            else {
                error = .invalidResponse
                return
            }
            let nonce = rawNonce
            run { try await account.signInWithApple(idToken: token, rawNonce: nonce) }
        case .failure(let failure):
            // Cancelling isn't an error.
            if (failure as? ASAuthorizationError)?.code != .canceled { error = .authRejected("apple") }
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in characters[Int.random(in: 0..<characters.count, using: &generator)] })
    }

    private func run(_ work: @escaping () async throws -> Void) {
        // The keyboard goes, so the answer (or the message) is in view.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        isWorking = true
        error = nil
        Task {
            do {
                try await work()
            } catch {
                self.error = BackendError.from(error)
            }
            isWorking = false
        }
    }
}

/// A calm line for a backend error. Never blames the user.
struct AccountErrorText: View {
    let error: BackendError

    var body: some View {
        Text(error.message)
            .vessTextStyle(.bodyS)
            .foregroundStyle(VESSColor.warningText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("account.error")
    }
}

extension BackendError {
    /// What the user reads.
    var message: LocalizedStringResource {
        switch self {
        case .notSignedIn: "Please sign in again."
        case .dailyLimit: "That's today's free uses. Back tomorrow."
        case .notConfigured: "This isn't available yet. Try again later."
        case .busy: "AI is busy right now. Try again in a little while. This didn't use an estimate."
        case .upstream: "That didn't go through. Try again in a moment."
        case .offline: "You're offline. Try again when you're connected."
        case .authRejected(let code) where code.contains("otp") || code.contains("expired") || code.contains("invalid"):
            "That code didn't work. Check it, or send a new one."
        case .authRejected(let code) where code.contains("rate") || code.contains("over_"):
            "Too many tries for now. Wait a minute and try again."
        case .authRejected: "Signing in didn't work. Try again."
        case .badRequest, .server, .invalidResponse: "Something went wrong. Try again in a moment."
        }
    }
}
