#if os(iOS)
import SwiftUI
import AccountKit
import DesignSystem

/// The account decision intentionally precedes host pairing. Standard accounts
/// enable recovery and device management; the offline route remains account-free
/// and never creates a Supabase request.
public struct AccountEntryView: View {
    @Bindable private var account: AccountSessionController
    private let onComplete: () -> Void

    @State private var route: Route = .choice
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var messageIsError = false
    @State private var showPasswordReset = false
    @State private var resetPassword = ""
    @State private var passwordResetCallback: URL?
    @Environment(\.lancerTokens) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Route { case choice, signIn, signUp, offline }

    public init(account: AccountSessionController, onComplete: @escaping () -> Void) {
        _account = Bindable(account)
        self.onComplete = onComplete
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Same branded hero every other onboarding screen uses (see
                // OnboardingHeroBanner) — this screen previously fell back to a flat
                // background with a small mono wordmark, breaking the visual identity
                // the carousel establishes right before it. Full-bleed, NOT inside the
                // 560pt content constraint below, or it stops spanning full width on
                // iPad/wide screens.
                OnboardingHeroBanner(eyebrow: "lancer", title: headline, subtitle: subtitle)

                VStack(alignment: .leading, spacing: 18) {
                    switch route {
                    case .choice:  choiceCards
                    case .offline: offlineForm
                    default:       credentialsForm
                    }

                    if let message {
                        Text(message)
                            .font(.dsSansPt(13, weight: .medium))
                            .foregroundStyle(messageIsError ? t.danger : t.ok)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityHint("Account status")
                    }
                }
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: route)
        .sheet(isPresented: $showPasswordReset) { passwordResetSheet }
        .onReceive(NotificationCenter.default.publisher(for: .lancerAuthCallback)) { note in
            guard let callback = note.object as? URL, callback.host == "auth" else { return }
            passwordResetCallback = callback
            resetPassword = ""
            showPasswordReset = true
        }
    }

    private var headline: String {
        switch route {
        case .choice:  "Choose how\nyou connect."
        case .signUp:  "Create your\nLancer account."
        case .signIn:  "Welcome back."
        case .offline: "What should we\ncall you?"
        }
    }

    private var subtitle: String {
        switch route {
        case .choice:
            "Use an account for recovery, device management, and billing, or keep your existing account-free pairing setup completely offline."
        case .signUp:
            "Email confirmation is required. Your password is never shared with your machines."
        case .signIn:
            "Use the email and password for your Lancer account."
        case .offline:
            "Your name personalizes the app on this device. No account, no Supabase — you pair directly with your own machine."
        }
    }

    private var choiceCards: some View {
        VStack(spacing: 12) {
            Button {
                Haptics.selection()
                route = .signUp
                message = nil
            } label: {
                accountChoiceCard(
                    title: "Lancer account",
                    detail: "Email sign-in, password recovery, and registered devices.",
                    icon: "person.crop.circle.badge.checkmark",
                    emphasized: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("accountStandardChoice")

            Button {
                Haptics.selection()
                route = .offline
                message = nil
            } label: {
                accountChoiceCard(
                    title: "Self-hosted offline",
                    detail: "Pair directly with your own machine. No Supabase, recovery, device list, or hosted billing.",
                    icon: "lock.shield",
                    emphasized: false
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("accountOfflineChoice")

            Button("I already have an account") {
                Haptics.selection()
                route = .signIn
                message = nil
            }
            .font(.dsSansPt(14, weight: .semibold))
            .foregroundStyle(t.accent)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }

    private func accountChoiceCard(title: String, detail: String, icon: String, emphasized: Bool) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(emphasized ? t.accentFg : t.accent)
                .frame(width: 42, height: 42)
                .background(emphasized ? t.accent : t.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.dsDisplayPt(18, weight: .bold)).foregroundStyle(t.text)
                Text(detail).font(.dsSansPt(13)).foregroundStyle(t.text3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(t.text4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(emphasized ? t.accent.opacity(0.55) : t.border, lineWidth: 1))
    }

    @ViewBuilder
    private func labeledField(_ label: String) -> some View {
        Text(label).font(.dsMonoPt(10, weight: .medium)).tracking(1).foregroundStyle(t.text4)
    }

    private var offlineForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                labeledField("YOUR NAME")
                TextField("Ada Lovelace", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .padding(13)
                    .background(t.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.border, lineWidth: 1))
                    .accessibilityIdentifier("offlineNameField")
            }
            DSButton("continue", variant: .primary, size: .lg, isLoading: isWorking, fullWidth: true) {
                Task {
                    isWorking = true
                    await account.useSelfHostedOffline(name: name)
                    isWorking = false
                    Haptics.success()
                    onComplete()
                }
            }
            .disabled(isWorking || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("offlineContinue")

            Button("Back") { Haptics.selection(); route = .choice; message = nil }
                .font(.dsSansPt(13, weight: .semibold))
                .foregroundStyle(t.accent)
        }
        .padding(16)
        .background(t.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var credentialsForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            if route == .signUp {
                VStack(alignment: .leading, spacing: 7) {
                    labeledField("YOUR NAME")
                    TextField("Ada Lovelace", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .padding(13)
                        .background(t.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.border, lineWidth: 1))
                        .accessibilityIdentifier("accountNameField")
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("EMAIL").font(.dsMonoPt(10, weight: .medium)).tracking(1).foregroundStyle(t.text4)
                TextField("you@example.com", text: $email)
                    .textInputAutocapitalization(.never)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .padding(13)
                    .background(t.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.border, lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("PASSWORD").font(.dsMonoPt(10, weight: .medium)).tracking(1).foregroundStyle(t.text4)
                SecureField(route == .signUp ? "At least 12 characters" : "Your password", text: $password)
                    .textContentType(route == .signUp ? .newPassword : .password)
                    .padding(13)
                    .background(t.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.border, lineWidth: 1))
            }
            DSButton(route == .signUp ? "create account" : "sign in", variant: .primary, size: .lg, isLoading: isWorking, fullWidth: true) {
                Task { await submitCredentials() }
            }
            .disabled(
                isWorking
                || (route == .signUp && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || password.isEmpty
            )
            .accessibilityIdentifier(route == .signUp ? "accountSignUp" : "accountSignIn")

            HStack {
                Button(route == .signUp ? "Already have an account? Sign in" : "Create an account") {
                    Haptics.selection()
                    route = route == .signUp ? .signIn : .signUp
                    message = nil
                }
                .font(.dsSansPt(13, weight: .semibold))
                .foregroundStyle(t.accent)
                Spacer()
                if route == .signIn {
                    Button("Forgot password?") { showPasswordReset = true }
                        .font(.dsSansPt(13, weight: .semibold))
                        .foregroundStyle(t.accent)
                }
            }

            // Back to the connection-choice screen (this view has no top-bar back).
            Button("Back") { Haptics.selection(); route = .choice; message = nil }
                .font(.dsSansPt(13, weight: .semibold))
                .foregroundStyle(t.text3)
                .accessibilityLabel("Back to connection choice")
        }
        .padding(16)
        .background(t.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var passwordResetSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if passwordResetCallback != nil {
                    Text("Choose a new password").font(.dsDisplayPt(24, weight: .bold))
                    Text("Use at least 12 characters. This link is consumed only by Lancer.")
                        .font(.dsSansPt(14)).foregroundStyle(t.text3).fixedSize(horizontal: false, vertical: true)
                    SecureField("New password", text: $resetPassword)
                        .textContentType(.newPassword)
                        .textFieldStyle(.roundedBorder)
                    DSButton("save new password", variant: .primary, isLoading: isWorking, fullWidth: true) {
                        Task { await completePasswordReset() }
                    }
                } else {
                    Text("Reset password").font(.dsDisplayPt(24, weight: .bold))
                    Text("We’ll send a reset link to this email. The app opens lancer://auth/callback to finish securely.")
                        .font(.dsSansPt(14)).foregroundStyle(t.text3).fixedSize(horizontal: false, vertical: true)
                    TextField("you@example.com", text: $email)
                        .textInputAutocapitalization(.never)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textFieldStyle(.roundedBorder)
                    DSButton("send reset link", variant: .primary, isLoading: isWorking, fullWidth: true) {
                        Task { await sendPasswordReset() }
                    }
                }
                if let message { Text(message).font(.dsSansPt(13)).foregroundStyle(messageIsError ? t.danger : t.ok) }
                Spacer()
            }
            .padding(24)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showPasswordReset = false } } }
        }
    }

    private func submitCredentials() async {
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            if route == .signUp {
                let result = try await account.signUp(name: name, email: email, password: password)
                if result.confirmationRequired {
                    message = "Check your email to confirm your account, then sign in."
                    messageIsError = false
                    Haptics.success()
                } else {
                    Haptics.success()
                    onComplete()
                }
            } else {
                try await account.signIn(email: email, password: password)
                Haptics.success()
                onComplete()
            }
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "We couldn't complete that request. Try again."
            messageIsError = true
            Haptics.error()
        }
    }

    private func sendPasswordReset() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await account.requestPasswordReset(email: email)
            message = "If an account exists for that email, a reset link is on its way."
            messageIsError = false
            Haptics.success()
        } catch {
            message = "We couldn't send a reset link. Try again shortly."
            messageIsError = true
            Haptics.error()
        }
    }

    private func completePasswordReset() async {
        guard let callback = passwordResetCallback else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await account.completePasswordReset(callbackURL: callback, newPassword: resetPassword)
            passwordResetCallback = nil
            showPasswordReset = false
            message = "Password updated. You're signed in."
            messageIsError = false
            Haptics.success()
            onComplete()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "We couldn't update your password."
            messageIsError = true
            Haptics.error()
        }
    }
}
#endif
