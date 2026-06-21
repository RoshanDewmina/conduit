#if os(iOS)
import SwiftUI
import DesignSystem
import UIKit

/// Optional onboarding screen explaining how to turn on Remote Login / sshd so
/// Conduit can open a live terminal on the user's Mac or Linux box. Purely
/// instructional — no SSH/network calls happen here. The caller wires
/// `onAddHost` to present `WorkspacesFeature.AddHostView` and `onSkip` to
/// advance the flow without setting anything up now.
public struct OnboardingSSHSetupScreen: View {
    public let onAddHost: () -> Void
    public let onSkip: () -> Void

    @Environment(\.conduitTokens) private var t
    @State private var copiedSnippetID: String?

    public init(onAddHost: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.onAddHost = onAddHost
        self.onSkip = onSkip
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 28)

                VStack(alignment: .leading, spacing: 22) {
                    OnboardingSSHStepRow(
                        number: 1,
                        title: "Turn on Remote Login",
                        detail: "On your Mac: System Settings → General → Sharing → enable Remote Login. It's a single toggle. (Linux: make sure sshd is running.)"
                    )

                    OnboardingSSHStepRow(
                        number: 2,
                        title: "Find your details",
                        detail: "Open Terminal on your Mac and run these two commands — they print the username and computer name you'll need next."
                    ) {
                        VStack(spacing: 8) {
                            OnboardingSSHCodeSnippet(
                                id: "whoami",
                                command: "whoami",
                                caption: "your username",
                                isCopied: copiedSnippetID == "whoami",
                                onCopy: { copy("whoami", id: "whoami") }
                            )
                            OnboardingSSHCodeSnippet(
                                id: "computerName",
                                command: "scutil --get ComputerName",
                                caption: "your computer's name",
                                isCopied: copiedSnippetID == "computerName",
                                onCopy: { copy("scutil --get ComputerName", id: "computerName") }
                            )
                        }
                    }

                    OnboardingSSHStepRow(
                        number: 3,
                        title: "Add your machine in Conduit",
                        detail: "Tap “Add a machine” below and paste ssh you@your-computer.local — using the username and name from step 2."
                    )

                    OnboardingSSHStepRow(
                        number: 4,
                        title: "Generate a key (one tap)",
                        detail: "In Add Machine, pick Ed25519 and tap Generate key. Conduit creates and stores it securely on your phone."
                    )

                    OnboardingSSHStepRow(
                        number: 5,
                        title: "Authorize it",
                        detail: "Copy the one line Conduit shows and paste it into your Mac's Terminal — it appends your key to ~/.ssh/authorized_keys. Then tap Connect & Save."
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)

                footerNote
                    .padding(.horizontal, 24)
                    .padding(.top, 26)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(t.bg.ignoresSafeArea())
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .safeAreaInset(edge: .bottom) {
            actions
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 16)
                .background(t.bg.ignoresSafeArea(edges: .bottom))
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(t.accentSoft)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(t.accent)
                    )
                Text("OPTIONAL SETUP")
                    .font(.dsMonoPt(10, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(t.text4)
            }
            Text("Enable SSH")
                .font(.dsDisplayPt(28, weight: .heavy))
                .foregroundStyle(t.text)
                .padding(.top, 6)
            Text("Turn on SSH so Conduit can open a live terminal on your Mac.")
                .font(.dsSansPt(14))
                .foregroundStyle(t.text3)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    // MARK: Footer note

    private var footerNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(t.text4)
                .padding(.top, 1)
            Text("You only need this for the live terminal. Approvals and agent runs already work over the relay without SSH.")
                .font(.dsSansPt(12.5))
                .foregroundStyle(t.text4)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(t.surface2)
        )
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 10) {
            DSButton("Add a machine →", variant: .accent, size: .lg, fullWidth: true) {
                Haptics.selection()
                onAddHost()
            }
            .accessibilityIdentifier("sshSetupAddHost")

            Button {
                Haptics.selection()
                onSkip()
            } label: {
                Text("Skip — I'll do this later")
                    .font(.dsSansPt(13, weight: .medium))
                    .foregroundStyle(t.text3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sshSetupSkip")
        }
    }

    // MARK: Copy

    private func copy(_ text: String, id: String) {
        UIPasteboard.general.string = text
        Haptics.selection()
        copiedSnippetID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if copiedSnippetID == id { copiedSnippetID = nil }
        }
    }
}

// MARK: - Step row

private struct OnboardingSSHStepRow<Accessory: View>: View {
    let number: Int
    let title: String
    let detail: String
    @ViewBuilder var accessory: () -> Accessory

    @Environment(\.conduitTokens) private var t

    init(
        number: Int,
        title: String,
        detail: String,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.number = number
        self.title = title
        self.detail = detail
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(t.surface2)
                .frame(width: 36, height: 36)
                .overlay(
                    Text("\(number)")
                        .font(.dsMonoPt(14, weight: .semibold))
                        .foregroundStyle(t.accent)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.dsSansPt(15, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(detail)
                    .font(.dsSansPt(12.5))
                    .foregroundStyle(t.text4)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                accessory()
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - Copyable mono code snippet

private struct OnboardingSSHCodeSnippet: View {
    let id: String
    let command: String
    let caption: String
    let isCopied: Bool
    let onCopy: () -> Void

    @Environment(\.conduitTokens) private var t

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(command)
                    .font(.dsMonoPt(13, weight: .medium))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                Text(caption)
                    .font(.dsSansPt(11))
                    .foregroundStyle(t.text4)
            }
            Spacer(minLength: 8)
            Button(action: onCopy) {
                HStack(spacing: 4) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                    Text(isCopied ? "Copied" : "Copy")
                        .font(.dsSansPt(12, weight: .medium))
                }
                .foregroundStyle(isCopied ? t.ok : t.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy \(command)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.border, lineWidth: 1)
        )
    }
}

#Preview("SSH setup guide") {
    OnboardingSSHSetupScreen(onAddHost: {}, onSkip: {})
        .environment(\.conduitTokens, .light)
}
#endif
