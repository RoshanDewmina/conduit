#if os(iOS)
import SwiftUI
import DesignSystem

// MARK: - Variant selector

public enum OnboardingVariant {
    case variantA   // full replace — 4 screens, highly visual, animated
    case variantB   // trim + animate — strongest beats from original 8 slides
}

// MARK: - OnboardingView (public shell)

/// Interactive, skippable, replayable multi-step onboarding walkthrough.
/// Pass `variant:` to select which treatment is displayed.
/// Accepts a `startAtStep` parameter so SettingsView can replay from step 0.
public struct OnboardingView: View {
    public let variant: OnboardingVariant
    public let onContinue: () -> Void
    public let onSetupWorkspace: () -> Void

    public init(
        variant: OnboardingVariant = .variantA,
        onContinue: @escaping () -> Void,
        onSetupWorkspace: @escaping () -> Void = {},
        startAtStep: Int = 0
    ) {
        self.variant = variant
        self.onContinue = onContinue
        self.onSetupWorkspace = onSetupWorkspace
    }

    public var body: some View {
        switch variant {
        case .variantA:
            OnboardingVariantAView(onComplete: onContinue)
        case .variantB:
            OnboardingVariantBView(onContinue: onContinue, onSetupWorkspace: onSetupWorkspace)
        }
    }
}

// MARK: - SSH platform enum (shared)

private enum SSHPlatform: String, CaseIterable, Identifiable {
    case macOS   = "macOS"
    case windows = "Windows"
    case linux   = "Linux"
    var id: String { rawValue }
}

// ============================================================
// MARK: - Variant A — Full replace (4 screens, highly visual)
// ============================================================

private struct OnboardingVariantAView: View {
    let onComplete: () -> Void

    @State private var currentStep: Int = 0
    @State private var animationDirection: Int = 1  // +1 forward, -1 back
    @Environment(\.conduitTokens) private var t

    private static let totalSteps = 4

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    stepSquares
                    Spacer()
                    if currentStep < Self.totalSteps - 1 {
                        Button("skip") { onComplete() }
                            .font(.dsMonoPt(12))
                            .foregroundStyle(t.text3)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // Slide content
                ZStack {
                    switch currentStep {
                    case 0:  slideWelcome.id("A-0")
                    case 1:  slideHowItWorks.id("A-1")
                    case 2:  slideSSHSetup.id("A-2")
                    default: slideGetStarted.id("A-3")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: animationDirection > 0 ? .trailing : .leading)
                            .combined(with: .opacity),
                        removal:   .move(edge: animationDirection > 0 ? .leading : .trailing)
                            .combined(with: .opacity)
                    )
                )
                .animation(.spring(response: 0.38, dampingFraction: 0.88), value: currentStep)

                // Bottom nav
                VStack(spacing: 14) {
                    navButtons
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .background(t.bg)
            }
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    let threshold: CGFloat = 55
                    if value.translation.width < -threshold { advance() }
                    else if value.translation.width > threshold { goBack() }
                }
        )
    }

    // MARK: Square step indicators (BLOCKS style)

    private var stepSquares: some View {
        HStack(spacing: 5) {
            ForEach(0..<Self.totalSteps, id: \.self) { i in
                Rectangle()
                    .fill(i == currentStep ? t.accent : t.border)
                    .frame(width: i == currentStep ? 16 : 6, height: 4)
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: currentStep)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    // MARK: Nav buttons

    @ViewBuilder
    private var navButtons: some View {
        if currentStep < Self.totalSteps - 1 {
            HStack(spacing: 12) {
                if currentStep > 0 {
                    DSButton("back", variant: .secondary, size: .lg, action: goBack)
                }
                DSButton(
                    "next",
                    icon: .chevronRight,
                    variant: .accent,
                    size: .lg,
                    fullWidth: currentStep == 0,
                    action: advance
                )
            }
        } else {
            VStack(spacing: 10) {
                DSButton("add host", icon: .plus,
                         variant: .accent, size: .lg, fullWidth: true,
                         action: onComplete)
            }
        }
    }

    // MARK: Navigation

    private func advance() {
        guard currentStep < Self.totalSteps - 1 else { return }
        animationDirection = 1
        withAnimation { currentStep += 1 }
    }

    private func goBack() {
        guard currentStep > 0 else { return }
        animationDirection = -1
        withAnimation { currentStep -= 1 }
    }

    // --------------------------------------------------------
    // MARK: Slide 1 — Welcome
    // --------------------------------------------------------

    private var slideWelcome: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 28) {
                Spacer(minLength: 16)

                // Wordmark
                Text("conduit")
                    .font(.dsDisplayPt(13, weight: .bold))
                    .foregroundStyle(t.text3)
                    .kerning(3.5)
                    .textCase(.uppercase)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                // DotMatrix hero
                DotMatrixView(state: .connecting, cols: 26, rows: 9, cell: 9, dot: 4)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                VStack(spacing: 10) {
                    Text("connect your\nfirst host")
                        .font(.dsDisplayPt(25, weight: .bold))
                        .foregroundStyle(t.text)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                    Text("A phone-native cockpit\nfor remote AI coding.")
                        .font(.dsMonoPt(12.5))
                        .foregroundStyle(t.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 260)
                }

                // Feature highlights
                VStack(alignment: .leading, spacing: 14) {
                    featureRow("connect", "SSH into any server in seconds.", icon: "bolt.fill")
                    featureRow("survive", "Sessions stay alive across Wi-Fi and cellular.", icon: "antenna.radiowaves.left.and.right")
                    featureRow("approve", "Review and approve agent tool calls on the go.", icon: "checkmark.seal.fill")
                    featureRow("review", "Warp-style block output, diffs, and logs.", icon: "doc.text.magnifyingglass")
                }
                .padding(.top, 4)

                // Spectrum bar footer
                SpectrumBar(mode: .idle, height: 4)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    // --------------------------------------------------------
    // MARK: Slide 2 — How it works (animated block mock)
    // --------------------------------------------------------

    private var slideHowItWorks: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                Spacer(minLength: 12)

                VStack(spacing: 10) {
                    Text("smart blocks.")
                        .font(.dsDisplayPt(30, weight: .bold))
                        .foregroundStyle(t.text)
                        .multilineTextAlignment(.center)
                    Text("Commands run in smart blocks. Each command is its own card.")
                        .font(.dsMonoPt(12.5))
                        .foregroundStyle(t.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 280)
                }

                // Animated block mock
                AnimatedBlockMockView()

                calloutCard(
                    header: {
                        Text("// terminal blocks")
                            .font(.dsMonoPt(12, weight: .bold))
                            .foregroundStyle(t.text3)
                    },
                    content: {
                        VStack(alignment: .leading, spacing: 8) {
                            modelPoint(icon: "rectangle.split.1x2",
                                       title: "one block per command",
                                       detail: "Header, output panel, and exit status — all tied together.")
                            modelPoint(icon: "sparkles",
                                       title: "inline AI agent",
                                       detail: "Run claude or codex and the block expands into a live agent view.")
                            modelPoint(icon: "display",
                                       title: "alt-screen apps",
                                       detail: "Vim and htop auto-escalate to a full-screen overlay and return on exit.")
                        }
                    }
                )

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    // --------------------------------------------------------
    // MARK: Slide 3 — SSH Setup (platform picker)
    // --------------------------------------------------------

    private var slideSSHSetup: some View {
        SSHSetupSlideView()
    }

    // --------------------------------------------------------
    // MARK: Slide 4 — Get started (BLOCKS spec primary screen)
    // --------------------------------------------------------

    private var slideGetStarted: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                Spacer(minLength: 12)

                // Wordmark
                Text("conduit")
                    .font(.dsDisplayPt(13, weight: .bold))
                    .foregroundStyle(t.text3)
                    .kerning(3.5)
                    .textCase(.uppercase)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                // DotMatrix hero
                DotMatrixView(state: .connecting, cols: 26, rows: 9, cell: 9, dot: 4)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                VStack(spacing: 10) {
                    Text("connect your\nfirst host")
                        .font(.dsDisplayPt(25, weight: .bold))
                        .foregroundStyle(t.text)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                    Text("Add an SSH host to start your first session.")
                        .font(.dsMonoPt(12.5))
                        .foregroundStyle(t.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 260)
                }

                // SQUARE terminal input row
                TerminalInputMockView()

                // Optional Anthropic key entry
                AnthropicKeyEntryView()

                // Secondary link
                HStack(spacing: 4) {
                    Text("or ")
                        .font(.dsMonoPt(11.5))
                        .foregroundStyle(t.text3)
                    // Pairing isn't shipped yet — render muted (not accent) so it
                    // reads as informational copy rather than a tappable link.
                    Text("scan a pairing code (soon)")
                        .font(.dsMonoPt(11.5))
                        .foregroundStyle(t.text3)
                }

                // Spectrum bar footer
                SpectrumBar(mode: .idle, height: 4)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Shared helpers

    private func featureRow(_ title: String, _ subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(t.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.dsMonoPt(13, weight: .bold))
                    .foregroundStyle(t.text)
                Text(subtitle)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text3)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func modelPoint(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(t.accent)
                .frame(width: 14, alignment: .center)
                .padding(.top, 1)
            (Text(title).fontWeight(.semibold) + Text(" \(detail)"))
                .font(.dsMonoPt(12))
                .foregroundStyle(t.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func calloutCard<Content: View, Header: View>(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header()
            content()
        }
        .padding(14)
        .background(t.surface)
        .overlay(
            Rectangle()
                .strokeBorder(t.border, lineWidth: 0.5)
        )
    }
}

// --------------------------------------------------------
// MARK: - Terminal input mock (BLOCKS style)
// --------------------------------------------------------

private struct TerminalInputMockView: View {
    @Environment(\.conduitTokens) private var t

    var body: some View {
        HStack(spacing: 0) {
            // Blue $ prompt
            Text("$")
                .font(.dsMonoPt(14, weight: .bold))
                .foregroundStyle(t.accent)
                .padding(.leading, 13)
                .padding(.trailing, 8)
            // Placeholder
            Text("ssh user@host")
                .font(.dsMonoPt(13))
                .foregroundStyle(t.text4)
            Spacer()
            // Blinking caret block
            BlinkingCaret()
                .padding(.trailing, 13)
        }
        .padding(.vertical, 12)
        .background(t.surfaceSunk)
        .overlay(
            Rectangle()
                .strokeBorder(t.border, lineWidth: 1)
        )
    }
}

private struct BlinkingCaret: View {
    @Environment(\.conduitTokens) private var t
    @State private var visible = true
    var body: some View {
        Rectangle()
            .fill(t.accent)
            .frame(width: 8, height: 14)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever()) {
                    visible.toggle()
                }
            }
    }
}

// --------------------------------------------------------
// MARK: - Animated block mock (Variant A slide 2)
// --------------------------------------------------------

private struct AnimatedBlockMockView: View {
    @Environment(\.conduitTokens) private var t
    @State private var visibleLines: Int = 0

    private let outputLines = [
        "Cloning repo…",
        "Installing dependencies…",
        "Running tests…",
        "✓  All 47 tests passed",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Block header bar
            HStack(spacing: 8) {
                // Tiny PixelBox in streaming state
                PixelBox(state: .streaming, size: 10, gap: 1, subdivisions: 1)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                Text("$ git clone && npm install && npm test")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.termText)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(t.termSurface2)

            // Output panel
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<min(visibleLines, outputLines.count), id: \.self) { i in
                    Text(outputLines[i])
                        .font(.dsMonoPt(12))
                        .foregroundStyle(i == outputLines.count - 1 ? t.termOk : t.termText2)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if visibleLines < outputLines.count {
                    BlinkingCursor()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.termSurface)

            // Exit chip row
            if visibleLines >= outputLines.count {
                HStack(spacing: 6) {
                    Text("exit 0")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.termOk)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(t.termOk.opacity(0.12))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(t.termSurface)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .clipShape(Rectangle())
        .overlay(
            Rectangle()
                .strokeBorder(t.termBorder, lineWidth: 0.5)
        )
        .animation(.easeOut(duration: 0.35), value: visibleLines)
        .onAppear { startAnimation() }
    }

    private func startAnimation() {
        visibleLines = 0
        for i in 0...outputLines.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.55) {
                withAnimation(.easeOut(duration: 0.3)) {
                    visibleLines = i
                }
            }
        }
    }
}

private struct BlinkingCursor: View {
    @Environment(\.conduitTokens) private var t
    @State private var visible = true
    var body: some View {
        Rectangle()
            .fill(t.accent.opacity(0.85))
            .frame(width: 7, height: 13)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                    visible.toggle()
                }
            }
    }
}

// --------------------------------------------------------
// MARK: - SSH Setup slide (shared A & B)
// --------------------------------------------------------

private struct SSHSetupSlideView: View {
    @Environment(\.conduitTokens) private var t
    @State private var selectedPlatform: SSHPlatform = .macOS

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                Spacer(minLength: 12)

                // Hero
                VStack(spacing: 10) {
                    // DotMatrix replacing icon hero
                    DotMatrixView(state: .connecting, cols: 16, rows: 5, cell: 9, dot: 4)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                    Text("enable SSH\non your server")
                        .font(.dsDisplayPt(24, weight: .bold))
                        .foregroundStyle(t.text)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                    Text("Pick your server's OS for exact setup steps.")
                        .font(.dsMonoPt(12.5))
                        .foregroundStyle(t.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 260)
                }

                // Platform picker — styled as mono segment strip
                SSHPlatformPicker(selected: $selectedPlatform)

                // Steps card — SQUARE
                VStack(alignment: .leading, spacing: 12) {
                    switch selectedPlatform {
                    case .macOS:   macOSSteps
                    case .windows: windowsSteps
                    case .linux:   linuxSteps
                    }
                }
                .padding(16)
                .background(t.surface)
                .overlay(
                    Rectangle()
                        .strokeBorder(t.border, lineWidth: 0.5)
                )
                .animation(.easeInOut(duration: 0.2), value: selectedPlatform)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: macOS

    private var macOSSteps: some View {
        VStack(alignment: .leading, spacing: 10) {
            sshStepLabel("1", "Open System Settings")
            sshStepLabel("2", "Go to General → Sharing")
            sshStepLabel("3", "Toggle Remote Login to on")
            sshStepLabel("4", "Allow access for your user account")
            Divider().background(t.divider)
            sshNote("Your Mac's SSH address is shown in the Sharing panel once enabled.")
        }
    }

    // MARK: Windows

    private var windowsSteps: some View {
        VStack(alignment: .leading, spacing: 10) {
            sshStepLabel("1", "Open Settings → System → Optional Features")
            sshStepLabel("2", "Search \"OpenSSH Server\" → Install")
            sshStepLabel("3", "Open Services (services.msc)")
            sshStepLabel("4", "Set OpenSSH SSH Server to Automatic → Start")
            Divider().background(t.divider)
            sshNote("Default port is 22. Allow it through Windows Firewall if prompted.")
        }
    }

    // MARK: Linux

    private var linuxSteps: some View {
        VStack(alignment: .leading, spacing: 10) {
            sshStepLabel("systemd", "sudo systemctl enable --now sshd")
            sshStepLabel("SysV", "sudo service ssh start")
            Divider().background(t.divider)
            sshNote("On Ubuntu/Debian, install first:\nsudo apt install openssh-server")
        }
    }

    // MARK: Step helpers

    private func sshStepLabel(_ badge: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(badge)
                .font(.dsMonoPt(11, weight: .bold))
                .foregroundStyle(t.accentFg)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(t.accent)
                .fixedSize()
            Text(text)
                .font(.dsMonoPt(13))
                .foregroundStyle(t.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sshNote(_ text: String) -> some View {
        Text(text)
            .font(.dsMonoPt(11.5))
            .foregroundStyle(t.text3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - SSH platform picker (BLOCKS style square tabs)

private struct SSHPlatformPicker: View {
    @Binding var selected: SSHPlatform
    @Environment(\.conduitTokens) private var t

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SSHPlatform.allCases) { platform in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selected = platform }
                } label: {
                    Text(platform.rawValue)
                        .font(.dsMonoPt(12, weight: .bold))
                        .foregroundStyle(selected == platform ? t.accentFg : t.text3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selected == platform ? t.accent : t.surfaceSunk)
                }
                if platform != SSHPlatform.allCases.last {
                    Rectangle()
                        .fill(t.border)
                        .frame(width: 1)
                }
            }
        }
        .overlay(
            Rectangle()
                .strokeBorder(t.border, lineWidth: 1)
        )
    }
}

// --------------------------------------------------------
// MARK: - Anthropic key entry (Variant A slide 4)
// --------------------------------------------------------

private struct AnthropicKeyEntryView: View {
    @Environment(\.conduitTokens) private var t
    @State private var apiKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("$")
                    .font(.dsMonoPt(11, weight: .bold))
                    .foregroundStyle(t.accent)
                Text("ANTHROPIC_API_KEY")
                    .font(.dsMonoPt(11, weight: .bold))
                    .foregroundStyle(t.text2)
                Text("(optional)")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }

            SecureField("sk-ant-…", text: $apiKey)
                .font(.dsMonoPt(13))
                .foregroundStyle(t.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(t.surfaceSunk)
                .overlay(
                    Rectangle()
                        .strokeBorder(t.border, lineWidth: 0.5)
                )

            Text("Paste your key from console.anthropic.com. It goes directly to the API and never leaves your device.")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(t.surface)
        .overlay(
            Rectangle()
                .strokeBorder(t.border, lineWidth: 0.5)
        )
    }
}

// ============================================================
// MARK: - Variant B — Trim + animate (original structure, enhanced)
// ============================================================

private struct OnboardingVariantBView: View {
    let onContinue: () -> Void
    let onSetupWorkspace: () -> Void

    @State private var currentStep: Int
    @State private var animationDirection: Int = 1
    @Environment(\.conduitTokens) private var t

    // Kept the strongest 5 beats: welcome, BYO, SSH setup, blocks, CTAs
    private static let totalSteps = 5

    init(onContinue: @escaping () -> Void, onSetupWorkspace: @escaping () -> Void, startAtStep: Int = 0) {
        self.onContinue = onContinue
        self.onSetupWorkspace = onSetupWorkspace
        _currentStep = State(initialValue: max(0, min(startAtStep, OnboardingVariantBView.totalSteps - 1)))
    }

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    stepCounterLabel
                    Spacer()
                    if currentStep < Self.totalSteps - 1 {
                        Button("skip") { onContinue() }
                            .font(.dsMonoPt(12))
                            .foregroundStyle(t.text3)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 8)

                // Slide with directional transitions
                ZStack {
                    switch currentStep {
                    case 0: bStepWelcome.id("B-0")
                    case 1: bStepBYOHost.id("B-1")
                    case 2: bStepSSHSetup.id("B-2")
                    case 3: bStepBlocks.id("B-3")
                    default: bStepCTAs.id("B-4")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: animationDirection > 0 ? .trailing : .leading)
                            .combined(with: .opacity),
                        removal:   .move(edge: animationDirection > 0 ? .leading : .trailing)
                            .combined(with: .opacity)
                    )
                )
                .animation(.spring(response: 0.38, dampingFraction: 0.88), value: currentStep)

                // Bottom controls
                VStack(spacing: 12) {
                    squareDotIndicators
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
                    if value.translation.width < -threshold { advance() }
                    else if value.translation.width > threshold { goBack() }
                }
        )
    }

    // MARK: Step counter

    private var stepCounterLabel: some View {
        Text("\(currentStep + 1)/\(Self.totalSteps)")
            .font(.dsMonoPt(12))
            .foregroundStyle(t.text3)
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    // MARK: Square dot indicators (BLOCKS style)

    private var squareDotIndicators: some View {
        HStack(spacing: 5) {
            ForEach(0..<Self.totalSteps, id: \.self) { index in
                Rectangle()
                    .fill(index == currentStep ? t.accent : t.border)
                    .frame(width: index == currentStep ? 16 : 6, height: 4)
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    // MARK: Action buttons

    @ViewBuilder
    private var actionButtons: some View {
        if currentStep < Self.totalSteps - 1 {
            HStack(spacing: 12) {
                if currentStep > 0 {
                    DSButton("back", variant: .secondary, size: .lg, action: goBack)
                }
                DSButton("next", icon: .chevronRight, variant: .accent, size: .lg,
                         fullWidth: currentStep == 0, action: advance)
            }
        } else {
            VStack(spacing: 10) {
                DSButton("add host", icon: .plus,
                         variant: .accent, size: .lg, fullWidth: true,
                         action: onContinue)
                VStack(spacing: 4) {
                    DSButton("set up a workspace for me", systemImage: "wand.and.stars",
                             variant: .secondary, size: .lg, fullWidth: true,
                             action: onSetupWorkspace)
                    Text("provision a new Fly.io VM · Beta")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text4)
                }
            }
        }
    }

    // MARK: Navigation

    private func advance() {
        guard currentStep < Self.totalSteps - 1 else { return }
        animationDirection = 1
        withAnimation { currentStep += 1 }
    }

    private func goBack() {
        guard currentStep > 0 else { return }
        animationDirection = -1
        withAnimation { currentStep -= 1 }
    }

    // --------------------------------------------------------
    // MARK: B-Slide 1 — Welcome
    // --------------------------------------------------------

    private var bStepWelcome: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                Spacer(minLength: 12)

                // Wordmark
                Text("conduit")
                    .font(.dsDisplayPt(13, weight: .bold))
                    .foregroundStyle(t.text3)
                    .kerning(3.5)
                    .textCase(.uppercase)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                // DotMatrix replacing PixelBox logo
                DotMatrixView(state: .connecting, cols: 26, rows: 9, cell: 9, dot: 4)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                VStack(spacing: 8) {
                    Text("connect your\nfirst host")
                        .font(.dsDisplayPt(25, weight: .bold))
                        .foregroundStyle(t.text)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                    Text("A phone-native cockpit for remote AI coding.")
                        .font(.dsMonoPt(12.5))
                        .foregroundStyle(t.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 260)
                }

                bFeatureGrid

                // Spectrum bar
                SpectrumBar(mode: .idle, height: 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private var bFeatureGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            bFeatureRow("attach", "Connect to your remote workspace in seconds.", icon: "bolt")
            bFeatureRow("survive", "Sessions stay alive across Wi-Fi and cellular.", icon: "antenna.radiowaves.left.and.right")
            bFeatureRow("approve", "See and approve agent actions from your phone.", icon: "checkmark.seal")
            bFeatureRow("review", "Diffs, logs, and tests on a phone-sized screen.", icon: "doc.text.magnifyingglass")
        }
        .padding(.top, 4)
    }

    // --------------------------------------------------------
    // MARK: B-Slide 2 — BYO-host model
    // --------------------------------------------------------

    private var bStepBYOHost: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                bStepHero(icon: "server.rack", headline: "no account.\nno subscription.")
                bCalloutCard(
                    header: {
                        Text("// how conduit works")
                            .font(.dsMonoPt(12, weight: .bold))
                            .foregroundStyle(t.text3)
                    },
                    content: {
                        VStack(alignment: .leading, spacing: 8) {
                            bModelPoint(icon: "server.rack", title: "your server",
                                        detail: "Any SSH host — a VPS, cloud VM, or local machine.")
                            bModelPoint(icon: "key.fill", title: "your API key",
                                        detail: "Paste your Anthropic key. It goes directly to the provider.")
                            bModelPoint(icon: "person.badge.minus", title: "no account needed",
                                        detail: "No Conduit login. Data stays on your device.")
                        }
                    }
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    // --------------------------------------------------------
    // MARK: B-Slide 3 — SSH Setup (platform picker, same content as Variant A)
    // --------------------------------------------------------

    private var bStepSSHSetup: some View {
        SSHSetupSlideView()
    }

    // --------------------------------------------------------
    // MARK: B-Slide 4 — Blocks
    // --------------------------------------------------------

    private var bStepBlocks: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                Spacer(minLength: 12)

                // DotMatrix replacing PixelBox thinking state
                DotMatrixView(state: .connecting, cols: 20, rows: 7, cell: 9, dot: 4)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                Text("warp-style\ncommand blocks.")
                    .font(.dsDisplayPt(24, weight: .bold))
                    .foregroundStyle(t.text)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                bCalloutCard(
                    header: {
                        Text("// terminal blocks")
                            .font(.dsMonoPt(12, weight: .bold))
                            .foregroundStyle(t.text3)
                    },
                    content: {
                        VStack(alignment: .leading, spacing: 8) {
                            bModelPoint(icon: "rectangle.split.1x2",
                                        title: "one block per command",
                                        detail: "Header, output, and exit status — always tied together.")
                            bModelPoint(icon: "sparkles",
                                        title: "inline AI agent",
                                        detail: "Run claude and the block expands into a live agent view.")
                            bModelPoint(icon: "display",
                                        title: "alt-screen apps",
                                        detail: "Vim and htop auto-escalate to full-screen raw terminal.")
                        }
                    }
                )

                SpectrumBar(mode: .scan, height: 4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    // --------------------------------------------------------
    // MARK: B-Slide 5 — Final CTAs (BLOCKS primary spec)
    // --------------------------------------------------------

    private var bStepCTAs: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                Spacer(minLength: 12)

                // Wordmark
                Text("conduit")
                    .font(.dsDisplayPt(13, weight: .bold))
                    .foregroundStyle(t.text3)
                    .kerning(3.5)
                    .textCase(.uppercase)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                // DotMatrix hero
                DotMatrixView(state: .connecting, cols: 26, rows: 9, cell: 9, dot: 4)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                VStack(spacing: 8) {
                    Text("you're ready.")
                        .font(.dsDisplayPt(25, weight: .bold))
                        .foregroundStyle(t.text)
                        .multilineTextAlignment(.center)
                    Text("Add a host to start your first session, or let Conduit provision a cloud workspace for you.")
                        .font(.dsMonoPt(12.5))
                        .foregroundStyle(t.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 260)
                }

                // SQUARE terminal input row
                TerminalInputMockView()

                // Secondary link
                HStack(spacing: 4) {
                    Text("or ")
                        .font(.dsMonoPt(11.5))
                        .foregroundStyle(t.text3)
                    // Pairing isn't shipped yet — render muted (not accent) so it
                    // reads as informational copy rather than a tappable link.
                    Text("scan a pairing code (soon)")
                        .font(.dsMonoPt(11.5))
                        .foregroundStyle(t.text3)
                }

                // Spectrum bar footer
                SpectrumBar(mode: .idle, height: 4)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Variant B shared sub-views

    private func bStepHero(icon: String, headline: String) -> some View {
        VStack(spacing: 14) {
            // DotMatrix small panel replacing icon square
            DotMatrixView(state: .connecting, cols: 12, rows: 4, cell: 9, dot: 4)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .padding(.top, 12)
            Text(headline)
                .font(.dsDisplayPt(24, weight: .bold))
                .foregroundStyle(t.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
    }

    private func bCalloutCard<Content: View, Header: View>(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header()
            content()
        }
        .padding(14)
        .background(t.surface)
        .overlay(
            Rectangle()
                .strokeBorder(t.border, lineWidth: 0.5)
        )
    }

    private func bModelPoint(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(t.accent)
                .frame(width: 14, alignment: .center)
                .padding(.top, 1)
            (Text(title).fontWeight(.semibold) + Text(" \(detail)"))
                .font(.dsMonoPt(12))
                .foregroundStyle(t.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bFeatureRow(_ title: String, _ subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(t.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.dsMonoPt(13, weight: .bold))
                    .foregroundStyle(t.text)
                Text(subtitle)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text3)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#endif
