#if os(iOS)
import SwiftUI
import DesignSystem

/// Visual-only clone of the approved onboarding sequence (see
/// `docs/design-audit/workflows/01-onboarding-pairing.md`), built on the
/// Cursor-style component language rather than `DesignSystem`. Every "advance"
/// action here just increments `step` — no real pairing, permission request,
/// or account creation happens. Not yet wired into `AppRoot`; that happens in
/// a separate pass.
public struct CursorOnboardingView: View {
    @Environment(\.cursorShellLiveBridge) private var liveBridge
    @Environment(\.cursorScheme) private var cursorScheme
    @State private var step: Int = 0
    @State private var showInvalidCodePreview: Bool = false
    private let onComplete: () -> Void

    public init(onComplete: @escaping () -> Void = {}) {
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CursorColors.resolve(cursorScheme).background.ignoresSafeArea())
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            CursorOnboardingProductProofStep(onGetStarted: { advance() })
        case 1:
            CursorOnboardingPairingStep(
                showInvalidCodePreview: $showInvalidCodePreview,
                onContinue: {
                    liveBridge?.onRequestPairing?()
                    advance()
                }
            )
        case 2:
            CursorOnboardingNotificationsStep(
                onEnable: { advance() },
                onNotNow: { advance() }
            )
        case 3:
            CursorOnboardingPolicyStep(
                onContinueRecommended: { advance() },
                onCustomize: { advance() }
            )
        default:
            CursorOnboardingAccountStep(
                onAddAccount: { onComplete() },
                onSkip: { onComplete() }
            )
        }
    }

    private func advance() {
        step += 1
    }
}

// MARK: - Step 1: Product proof

private struct CursorOnboardingProductProofStep: View {
    @Environment(\.cursorScheme) private var cursorScheme
    let onGetStarted: () -> Void

    var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Steer AI coding agents\nfrom your phone.")
                    .font(CursorType.pageTitle)
                    .foregroundColor(colors.primaryText)
                Text("Pair this phone with your machine, review risky actions, and keep work moving without opening a laptop.")
                    .font(CursorType.bodyText)
                    .foregroundColor(colors.secondaryText)
            }

            CursorArtifactCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        CursorStatusBadge(kind: .risk(level: .medium), label: "Medium risk")
                        Spacer()
                        Text("lancer-ios")
                            .font(CursorType.rowSecondary)
                            .foregroundColor(colors.secondaryText)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pending approval")
                            .font(CursorType.cardTitle)
                            .foregroundColor(colors.primaryText)
                        Text("Run `rm -rf .build` and reinstall dependencies to clear a stale cache.")
                            .font(CursorType.rowSecondary)
                            .foregroundColor(colors.secondaryText)
                    }

                    HStack(spacing: 10) {
                        CursorPillButton(title: "Deny", style: .secondary, action: {})
                        CursorPillButton(title: "Approve", style: .primary, action: {})
                    }
                }
            }
            .allowsHitTesting(false)

            CursorPillButton(title: "Get started", style: .primary, action: onGetStarted)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Step 2: Code-only pairing

private struct CursorOnboardingPairingStep: View {
    @Environment(\.cursorScheme) private var cursorScheme
    @Binding var showInvalidCodePreview: Bool
    let onContinue: () -> Void

    private let digitCount = 6

    var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pair your machine")
                    .font(CursorType.pageTitle)
                    .foregroundColor(colors.primaryText)
                Text("Lancer connects to the coding-agent CLIs already running on your computer.")
                    .font(CursorType.bodyText)
                    .foregroundColor(colors.secondaryText)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("On your machine, run `lancerd pair`")
                    .font(CursorType.inlineCode)
                    .foregroundColor(colors.secondaryText)

                digitRow

                if showInvalidCodePreview {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(colors.dangerRed)
                        Text("That code didn't match — check it and try again.")
                            .font(CursorType.rowSecondary)
                            .foregroundColor(colors.dangerRed)
                    }
                }
            }

            Button(action: { showInvalidCodePreview.toggle() }) {
                Text(showInvalidCodePreview ? "Hide error state" : "Preview error state")
                    .font(CursorType.rowSecondary)
                    .foregroundColor(colors.mutedText)
            }
            .buttonStyle(.plain)

            CursorPillButton(title: "Continue", style: .primary, action: onContinue)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
    }

    private var digitRow: some View {
        HStack(spacing: 8) {
            ForEach(0..<digitCount, id: \.self) { index in
                digitBox(filled: showInvalidCodePreview ? sampleInvalidDigit(at: index) : sampleValidDigit(at: index))
            }
        }
    }

    private func sampleValidDigit(at index: Int) -> String {
        let digits = ["4", "2", "8", "1", "9", "5"]
        return digits[index]
    }

    private func sampleInvalidDigit(at index: Int) -> String {
        let digits = ["4", "2", "8", "1", "9", "0"]
        return digits[index]
    }

    private func digitBox(filled digit: String) -> some View {
        let colors = CursorColors.resolve(cursorScheme)
        return Text(digit)
            .font(.system(size: 22, weight: .semibold, design: .monospaced))
            .foregroundColor(showInvalidCodePreview ? colors.dangerRed : colors.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(showInvalidCodePreview ? colors.dangerRed : colors.hairline, lineWidth: showInvalidCodePreview ? 1.5 : 1)
            )
    }
}

// MARK: - Step 3: Notifications pre-prompt

private struct CursorOnboardingNotificationsStep: View {
    @Environment(\.cursorScheme) private var cursorScheme
    let onEnable: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        VStack(alignment: .leading, spacing: 20) {
            ZStack {
                Circle()
                    .fill(colors.cardBackground)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle().stroke(colors.hairline, lineWidth: 1)
                    )
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(colors.primaryText)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Turn on notifications")
                    .font(CursorType.pageTitle)
                    .foregroundColor(colors.primaryText)
                Text("Approvals need to reach you the moment an agent is waiting on a risky action, even when the app is closed.")
                    .font(CursorType.bodyText)
                    .foregroundColor(colors.secondaryText)
            }

            CursorPillButton(title: "Enable notifications", style: .primary, action: onEnable)
                .frame(maxWidth: .infinity)

            Button(action: onNotNow) {
                Text("Not now")
                    .font(CursorType.pillLabel)
                    .foregroundColor(colors.mutedText)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Step 4: Policy default

private struct CursorOnboardingPolicyStep: View {
    @Environment(\.cursorScheme) private var cursorScheme
    let onContinueRecommended: () -> Void
    let onCustomize: () -> Void

    var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose a policy")
                    .font(CursorType.pageTitle)
                    .foregroundColor(colors.primaryText)
                Text("You can change this any time in Settings.")
                    .font(CursorType.bodyText)
                    .foregroundColor(colors.secondaryText)
            }

            CursorArtifactCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Balanced")
                            .font(CursorType.cardTitle)
                            .foregroundColor(colors.primaryText)
                        Spacer()
                        Text("Recommended")
                            .font(CursorType.rowSecondary)
                            .foregroundColor(colors.successGreen)
                    }
                    Text("Low-risk file edits run automatically. Anything that touches git history, deletes files, or hits the network waits for your approval.")
                        .font(CursorType.rowSecondary)
                        .foregroundColor(colors.secondaryText)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: CursorMetrics.cardCornerRadius)
                    .stroke(colors.primaryText.opacity(0.16), lineWidth: 1.5)
            )

            CursorPillButton(title: "Continue with recommended", style: .primary, action: onContinueRecommended)
                .frame(maxWidth: .infinity)

            Button(action: onCustomize) {
                Text("Customize")
                    .font(CursorType.pillLabel)
                    .foregroundColor(colors.mutedText)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Step 5: Account choice (optional, skippable, last)

private struct CursorOnboardingAccountStep: View {
    @Environment(\.cursorScheme) private var cursorScheme
    let onAddAccount: () -> Void
    let onSkip: () -> Void

    var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Add a Lancer account?")
                    .font(CursorType.pageTitle)
                    .foregroundColor(colors.primaryText)
                Text("An account syncs pairings and settings across your devices. You can always add one later from Settings.")
                    .font(CursorType.bodyText)
                    .foregroundColor(colors.secondaryText)
            }

            CursorPillButton(title: "Add account", style: .primary, action: onAddAccount)
                .frame(maxWidth: .infinity)

            Button(action: onSkip) {
                Text("Skip for now")
                    .font(CursorType.rowSecondary)
                    .foregroundColor(colors.mutedText)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
    }
}
#endif
