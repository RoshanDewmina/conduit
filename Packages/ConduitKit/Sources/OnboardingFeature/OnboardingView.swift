#if os(iOS)
import SwiftUI
import DesignSystem

// MARK: - OnboardingView

/// Interactive, skippable, replayable multi-step onboarding walkthrough.
/// Accepts a `startAtStep` parameter so SettingsView can replay from step 0.
public struct OnboardingView: View {
    public var onContinue: () -> Void
    public var onSetupWorkspace: () -> Void

    @State private var currentStep: Int
    @Environment(\.conduitTokens) private var t

    private static let totalSteps = 8

    public init(
        onContinue: @escaping () -> Void,
        onSetupWorkspace: @escaping () -> Void = {},
        startAtStep: Int = 0
    ) {
        self.onContinue = onContinue
        self.onSetupWorkspace = onSetupWorkspace
        _currentStep = State(initialValue: max(0, min(startAtStep, OnboardingView.totalSteps - 1)))
    }

    public var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar: step counter + skip
                HStack {
                    stepCounterLabel
                    Spacer()
                    if currentStep < Self.totalSteps - 1 {
                        skipButton
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 8)

                // Page content
                TabView(selection: $currentStep) {
                    ForEach(0..<Self.totalSteps, id: \.self) { step in
                        stepPage(step)
                            .tag(step)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentStep)

                // Dot indicators + action buttons
                VStack(spacing: 14) {
                    dotIndicators
                    actionButtons
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .background(t.bg)
            }
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    let threshold: CGFloat = 60
                    if value.translation.width < -threshold {
                        advance()
                    } else if value.translation.width > threshold {
                        goBack()
                    }
                }
        )
    }

    // MARK: - Step counter

    private var stepCounterLabel: some View {
        Text("\(currentStep + 1) / \(Self.totalSteps)")
            .font(.dsSansPt(13))
            .foregroundStyle(t.text3)
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    // MARK: - Skip button

    private var skipButton: some View {
        Button("Skip") {
            onContinue()
        }
        .font(.dsSansPt(14))
        .foregroundStyle(t.text3)
    }

    // MARK: - Dot indicators

    private var dotIndicators: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.totalSteps, id: \.self) { index in
                Circle()
                    .fill(index == currentStep ? t.accent : t.border)
                    .frame(width: index == currentStep ? 8 : 6,
                           height: index == currentStep ? 8 : 6)
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    // MARK: - Action buttons

    @ViewBuilder
    private var actionButtons: some View {
        if currentStep < Self.totalSteps - 1 {
            // Steps 1–7: Next button + optional back
            HStack(spacing: 12) {
                if currentStep > 0 {
                    DSButton("Back", variant: .secondary, size: .lg, action: goBack)
                }
                DSButton("Next", icon: .chevronRight, variant: .accent, size: .lg,
                         fullWidth: currentStep == 0, action: advance)
            }
        } else {
            // Step 8 (final): two CTAs
            VStack(spacing: 10) {
                DSButton("Add your first host", icon: .plus,
                         variant: .accent, size: .lg, fullWidth: true,
                         action: onContinue)
                VStack(spacing: 4) {
                    DSButton("Set up a workspace for me", systemImage: "wand.and.stars",
                             variant: .secondary, size: .lg, fullWidth: true,
                             action: onSetupWorkspace)
                    Text("Provision a new Fly.io VM · Beta")
                        .font(.dsSansPt(11))
                        .foregroundStyle(t.text4)
                }
            }
        }
    }

    // MARK: - Navigation helpers

    private func advance() {
        guard currentStep < Self.totalSteps - 1 else { return }
        withAnimation(.easeInOut(duration: 0.3)) { currentStep += 1 }
    }

    private func goBack() {
        guard currentStep > 0 else { return }
        withAnimation(.easeInOut(duration: 0.3)) { currentStep -= 1 }
    }

    // MARK: - Step pages

    @ViewBuilder
    private func stepPage(_ step: Int) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                switch step {
                case 0:  stepWelcome
                case 1:  stepBYOHost
                case 2:  stepAddHost
                case 3:  stepSSHKeys
                case 4:  stepBlocks
                case 5:  stepInbox
                case 6:  stepPersistence
                default: stepCTAs
                }
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Step 1: Welcome

    private var stepWelcome: some View {
        VStack(spacing: 24) {
            PixelBox(color: t.accent, size: 56, gap: 6, subdivisions: 3)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .padding(.top, 20)
            VStack(spacing: 8) {
                Text("Conduit")
                    .font(.dsDisplayPt(36, weight: .bold))
                    .foregroundStyle(t.text)
                    .multilineTextAlignment(.center)
                Text("A phone-native cockpit for remote AI coding.")
                    .font(.dsSansPt(17))
                    .foregroundStyle(t.text3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            featureGrid
        }
    }

    private var featureGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureRow("Attach", "Connect to your remote workspace in seconds.", icon: "bolt")
            featureRow("Survive", "Sessions stay alive across Wi-Fi and cellular.", icon: "antenna.radiowaves.left.and.right")
            featureRow("Approve", "See and approve agent actions from your phone.", icon: "checkmark.seal")
            featureRow("Review", "Diffs, logs, and tests on a phone-sized screen.", icon: "doc.text.magnifyingglass")
        }
        .padding(.top, 8)
    }

    // MARK: - Step 2: BYO-host model

    private var stepBYOHost: some View {
        VStack(spacing: 24) {
            stepHero(icon: "server.rack", headline: "No account. No subscription.")
            calloutCard {
                VStack(alignment: .leading, spacing: 7) {
                    modelPoint(icon: "server.rack", title: "Your server",
                               detail: "Any SSH host — a VPS, cloud VM, or local machine.")
                    modelPoint(icon: "key.fill", title: "Your API key",
                               detail: "Paste your Anthropic or OpenAI key. It goes directly to the provider, never to Conduit.")
                    modelPoint(icon: "person.badge.minus", title: "No account needed",
                               detail: "No Conduit login. No subscription. Data stays on your device.")
                }
            } header: {
                Label("How Conduit works", systemImage: "info.circle.fill")
                    .font(.dsSansPt(13, weight: .semibold))
                    .foregroundStyle(t.text2)
            }
        }
    }

    // MARK: - Step 3: Add a host

    private var stepAddHost: some View {
        VStack(spacing: 24) {
            stepHero(icon: "plus.rectangle.on.folder", headline: "Add a host in seconds.")
            calloutCard {
                VStack(alignment: .leading, spacing: 7) {
                    modelPoint(icon: "rectangle.and.pencil.and.ellipsis",
                               title: "Host form",
                               detail: "Tap \"+\" on the Sessions screen to fill in hostname, username, and port.")
                    modelPoint(icon: "terminal",
                               title: "Shorthand import",
                               detail: "Type or paste an ssh URL — \"ssh user@host\" — and Conduit fills the fields automatically.")
                    modelPoint(icon: "tag",
                               title: "Tags",
                               detail: "Label hosts with tags like \"prod\", \"dev\", or \"staging\" for quick filtering.")
                }
            } header: {
                Label("Connecting to a host", systemImage: "network")
                    .font(.dsSansPt(13, weight: .semibold))
                    .foregroundStyle(t.text2)
            }
        }
    }

    // MARK: - Step 4: SSH keys & TOFU

    private var stepSSHKeys: some View {
        VStack(spacing: 24) {
            stepHero(icon: "key.fill", headline: "Your keys, your trust.")
            calloutCard {
                VStack(alignment: .leading, spacing: 7) {
                    modelPoint(icon: "key.fill",
                               title: "Ed25519 key generation",
                               detail: "Conduit generates a secure Ed25519 key pair on-device. The private key never leaves your phone.")
                    modelPoint(icon: "lock.shield",
                               title: "Biometric gate",
                               detail: "Each connection prompts Face ID or Touch ID before reading the private key from the Keychain.")
                    modelPoint(icon: "checkmark.seal",
                               title: "TOFU host verification",
                               detail: "On first connect you review and accept the host fingerprint. Conduit remembers it and alerts you if it ever changes.")
                }
            } header: {
                Label("SSH keys & trust", systemImage: "lock.fill")
                    .font(.dsSansPt(13, weight: .semibold))
                    .foregroundStyle(t.text2)
            }
        }
    }

    // MARK: - Step 5: Connect & blocks

    private var stepBlocks: some View {
        VStack(spacing: 24) {
            stepHero(icon: "terminal", headline: "Warp-style command blocks.")
            calloutCard {
                VStack(alignment: .leading, spacing: 7) {
                    modelPoint(icon: "rectangle.split.1x2",
                               title: "One block per command",
                               detail: "Every shell command gets its own block — header, output panel, and exit status — so output is always tied to the command that produced it.")
                    modelPoint(icon: "sparkles",
                               title: "Inline AI agent",
                               detail: "When you run claude or codex the block expands into a live agent view: thinking indicator, streaming output, and tool-use cards.")
                    modelPoint(icon: "display",
                               title: "Alt-screen apps",
                               detail: "Vim, htop, and tmux switch the session automatically into a full-screen raw terminal overlay and return to block view on exit.")
                }
            } header: {
                Label("Terminal blocks", systemImage: "terminal.fill")
                    .font(.dsSansPt(13, weight: .semibold))
                    .foregroundStyle(t.text2)
            }
        }
    }

    // MARK: - Step 6: The approval Inbox

    private var stepInbox: some View {
        VStack(spacing: 24) {
            stepHero(icon: "checkmark.seal", headline: "Approve agent actions on the go.")
            calloutCard {
                VStack(alignment: .leading, spacing: 7) {
                    modelPoint(icon: "tray.full",
                               title: "Approval Inbox",
                               detail: "When an AI agent needs permission to run a tool or modify a file, the request appears in your Inbox tab — even if you backgrounded the app.")
                    modelPoint(icon: "checkmark.circle",
                               title: "One-tap approve or deny",
                               detail: "Review the proposed action and the diff it would make. Approve or deny with a single tap.")
                    modelPoint(icon: "bell.badge",
                               title: "Push notifications",
                               detail: "Conduit sends a push notification so you never miss an approval request even when your phone is locked.")
                }
            } header: {
                Label("Approval Inbox", systemImage: "tray")
                    .font(.dsSansPt(13, weight: .semibold))
                    .foregroundStyle(t.text2)
            }
        }
    }

    // MARK: - Step 7: Persistence & tmux

    private var stepPersistence: some View {
        VStack(spacing: 24) {
            stepHero(icon: "arrow.clockwise", headline: "Sessions that survive.")
            calloutCard {
                VStack(alignment: .leading, spacing: 7) {
                    modelPoint(icon: "iphone.and.arrow.forward",
                               title: "Background survival",
                               detail: "Conduit keeps the SSH connection alive when you switch apps. Return to an ongoing session without missing any output.")
                    modelPoint(icon: "rectangle.3.group",
                               title: "tmux integration",
                               detail: "For long-running processes attach to an existing tmux session on connect. Your agent keeps running even if you close the app entirely.")
                    modelPoint(icon: "clock.arrow.circlepath",
                               title: "Reconnect & restore",
                               detail: "On reconnect Conduit re-fetches recent history so the block transcript picks up right where you left off.")
                }
            } header: {
                Label("Persistence", systemImage: "bolt.shield")
                    .font(.dsSansPt(13, weight: .semibold))
                    .foregroundStyle(t.text2)
            }
        }
    }

    // MARK: - Step 8: Final CTAs (content only; buttons live below)

    private var stepCTAs: some View {
        VStack(spacing: 24) {
            PixelBox(color: t.accent, size: 48, gap: 5, subdivisions: 3)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .padding(.top, 20)
            VStack(spacing: 8) {
                Text("You're ready.")
                    .font(.dsDisplayPt(32, weight: .bold))
                    .foregroundStyle(t.text)
                    .multilineTextAlignment(.center)
                Text("Add a host to start your first session, or let Conduit provision a cloud workspace for you.")
                    .font(.dsSansPt(16))
                    .foregroundStyle(t.text3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Shared sub-views

    private func stepHero(icon: String, headline: String) -> some View {
        VStack(spacing: 14) {
            ZStack {
                t.accentSoft
                    .clipShape(RoundedRectangle(cornerRadius: t.r5, style: .continuous))
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(t.accent)
            }
            .frame(width: 72, height: 72)
            .padding(.top, 12)
            Text(headline)
                .font(.dsDisplayPt(24, weight: .bold))
                .foregroundStyle(t.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func calloutCard<Content: View, Header: View>(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Header
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header()
            content()
        }
        .padding(14)
        .background(t.surface, in: RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous)
                .strokeBorder(t.border, lineWidth: 0.5)
        )
    }

    private func modelPoint(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(t.accent)
                .frame(width: 16, alignment: .center)
                .padding(.top, 1)
            (Text(title).fontWeight(.semibold) + Text(" \(detail)"))
                .font(.dsSansPt(13))
                .foregroundStyle(t.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func featureRow(_ title: String, _ subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(t.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.dsSansPt(16, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(subtitle)
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#endif
