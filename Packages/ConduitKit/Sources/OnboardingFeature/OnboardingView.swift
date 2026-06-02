#if os(iOS)
import SwiftUI
import DesignSystem
import SecurityKit
import NotificationsKit
import AgentKit

// MARK: - SSH platform enum (shared)

private enum SSHPlatform: String, CaseIterable, Identifiable {
    case macOS   = "macOS"
    case linux   = "Linux"
    case windows = "Windows"
    var id: String { rawValue }
}

// MARK: - OnboardingView (public — Hero C dark, 7 screens)

/// Dark onboarding walkthrough. 7 screens: Hero C welcome → how it works →
/// SSH setup → notification priming → Face ID priming → first-session coach →
/// managed-compute escape hatch.
public struct OnboardingView: View {
    public let onContinue: () -> Void
    public let onSetupWorkspace: () -> Void

    @State private var step: Int = 0
    @State private var animationDirection: Int = 1
    @Environment(\.conduitTokens) private var t

    fileprivate static let totalSteps = 7

    public init(
        onContinue: @escaping () -> Void,
        onSetupWorkspace: @escaping () -> Void = {}
    ) {
        self.onContinue = onContinue
        self.onSetupWorkspace = onSetupWorkspace
    }

    public var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Slide content fills the middle
                ZStack {
                    switch step {
                    case 0:  screen1Welcome.id("s0")
                    case 1:  screen2HowItWorks.id("s1")
                    case 2:  screen3SSH.id("s2")
                    case 3:  screen4Notifications.id("s3")
                    case 4:  screen5FaceID.id("s4")
                    case 5:  screen6Coach.id("s5")
                    default: screen7Compute.id("s6")
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
                .animation(.spring(response: 0.38, dampingFraction: 0.88), value: step)
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

    // MARK: Navigation helpers

    private func advance() {
        guard step < Self.totalSteps - 1 else { return }
        animationDirection = 1
        withAnimation { step += 1 }
    }

    private func goBack() {
        guard step > 0 else { return }
        animationDirection = -1
        withAnimation { step -= 1 }
    }

    // MARK: Step dots

    private var stepDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<Self.totalSteps, id: \.self) { i in
                Rectangle()
                    .fill(i == step ? t.accent : t.border)
                    .frame(width: i == step ? 16 : 6, height: 4)
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: step)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    // ================================================================
    // MARK: Screen 1 — Hero C (Welcome)
    // ================================================================

    private var screen1Welcome: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Full-width SpectrumBar at top
                SpectrumBar(mode: .working, height: 10)
                    .padding(.horizontal, 22)
                    .padding(.top, 16)

                // "conduit" wordmark below spectrum bar
                Text("conduit")
                    .font(.dsMonoPt(10, weight: .bold))
                    .foregroundStyle(t.text3)
                    .kerning(2.5)
                    .textCase(.uppercase)
                    .padding(.horizontal, 26)
                    .padding(.top, 10)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                // Big 3-line title
                VStack(alignment: .leading, spacing: 2) {
                    Text("attach.")
                        .foregroundStyle(t.text)
                    Text("survive.")
                        .foregroundStyle(t.text3)
                    Text("approve.")
                        .foregroundStyle(t.accent)
                }
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .lineSpacing(-1)
                .tracking(-0.8)
                .padding(.horizontal, 26)
                .padding(.top, 20)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                // Body
                Text("Six jobs, one cockpit. The phone-native home for your remote coding agents.")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text3)
                    .lineSpacing(8.4)
                    .frame(maxWidth: 230, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 26)
                    .padding(.top, 18)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                // CTAs
                VStack(spacing: 10) {
                    DSButton("get started", variant: .primary, size: .lg, fullWidth: true, action: advance)
                    Button {
                        // Already uses Conduit — skip to completion
                        onContinue()
                    } label: {
                        Text("i already use conduit")
                            .font(.dsMonoPt(13))
                            .foregroundStyle(t.text3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 26)
                .padding(.top, 32)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // ================================================================
    // MARK: Screen 2 — How it works
    // ================================================================

    private var screen2HowItWorks: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 40)

                // Title with _ in accent
                HStack(spacing: 0) {
                    Text("how it works")
                        .foregroundStyle(t.text)
                    Text("_")
                        .foregroundStyle(t.accent)
                }
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .padding(.horizontal, 26)

                // 3 feature rows
                VStack(alignment: .leading, spacing: 0) {
                    howItWorksRow(
                        icon: .server,
                        title: "Bring your own host",
                        body: "Any server you can SSH into — yours forever, free."
                    )
                    howItWorksRow(
                        icon: .key,
                        title: "Bring your own keys",
                        body: "API keys + SSH keys live in the Secure Enclave."
                    )
                    howItWorksRow(
                        icon: .inbox,
                        title: "Approve from anywhere",
                        body: "Agents ask; you approve from the lock screen."
                    )
                }
                .padding(.horizontal, 26)
                .padding(.top, 28)

                Spacer(minLength: 24)

                // Step dots + continue button
                VStack(spacing: 14) {
                    stepDots
                        .frame(maxWidth: .infinity, alignment: .center)
                    DSButton("continue", variant: .primary, size: .lg, fullWidth: true, action: advance)
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func howItWorksRow(icon: DSIcon, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // 40×40 square icon tile
            ZStack {
                Rectangle()
                    .fill(t.accentSoft)
                    .overlay(
                        Rectangle()
                            .strokeBorder(t.border, lineWidth: 1)
                    )
                DSIconView(icon, size: 18, color: t.accent)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.dsMonoPt(13, weight: .bold))
                    .foregroundStyle(t.text)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                Text(body)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 12)
    }

    // ================================================================
    // MARK: Screen 3 — Enable SSH
    // ================================================================

    private var screen3SSH: some View {
        SSHScreen(onContinue: advance, currentStep: step)
    }

    // ================================================================
    // MARK: Screen 4 — Notification priming
    // ================================================================

    private var screen4Notifications: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer(minLength: 40)

                // Icon tile 58×58
                ZStack {
                    Rectangle()
                        .fill(t.accentSoft)
                        .overlay(
                            Rectangle()
                                .strokeBorder(t.accent, lineWidth: 1)
                        )
                    DSIconView(.inbox, size: 26, color: t.accent)
                }
                .frame(width: 58, height: 58)
                .frame(maxWidth: .infinity, alignment: .center)

                // Title
                HStack(spacing: 0) {
                    Text("get approval pings")
                        .foregroundStyle(t.text)
                    Text("_")
                        .foregroundStyle(t.accent)
                }
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .padding(.horizontal, 26)
                .padding(.top, 18)

                // Body
                Text("When an agent needs you, Conduit notifies you instantly — approve right from the lock screen.")
                    .font(.dsMonoPt(11.5))
                    .foregroundStyle(t.text3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320)
                    .padding(.horizontal, 26)
                    .padding(.top, 12)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                // Fake lock-screen notification card
                fakeLockScreenCard
                    .padding(.horizontal, 26)
                    .padding(.top, 24)

                Spacer(minLength: 24)

                // Step dots + buttons
                VStack(spacing: 14) {
                    stepDots
                        .frame(maxWidth: .infinity, alignment: .center)
                    DSButton("enable notifications", variant: .primary, size: .lg, fullWidth: true) {
                        Task {
                            await Notifications.shared.registerCategories()
                            let _ = await Notifications.shared.requestAuthorization()
                            advance()
                        }
                    }
                    Button { advance() } label: {
                        Text("not now")
                            .font(.dsMonoPt(12))
                            .foregroundStyle(t.text3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private var fakeLockScreenCard: some View {
        HStack(spacing: 12) {
            // App icon — blue square with bolt
            ZStack {
                Rectangle()
                    .fill(t.accent)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("claude")
                        .font(.system(size: 11.5, weight: .semibold, design: .default))
                        .foregroundStyle(t.text)
                    Text("·")
                        .foregroundStyle(t.text3)
                    Text("needs approval")
                        .font(.system(size: 11.5, weight: .semibold, design: .default))
                        .foregroundStyle(t.text)
                }
                Text("npm run deploy --prod")
                    .font(.dsMonoPt(10))
                    .foregroundStyle(t.text3)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
        }
        .padding(14)
        .background(t.surface)
        .overlay(
            Rectangle()
                .strokeBorder(t.border, lineWidth: 0.5)
        )
    }

    // ================================================================
    // MARK: Screen 5 — Face ID priming
    // ================================================================

    private var screen5FaceID: some View {
        FaceIDScreen(onContinue: advance, currentStep: step)
    }

    // ================================================================
    // MARK: Screen 6 — First-session coach (static/coached)
    // ================================================================

    private var screen6Coach: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 24)

                // Header row — breadcrumb style
                VStack(alignment: .leading, spacing: 2) {
                    Text("first session")
                        .font(.dsMonoPt(10))
                        .foregroundStyle(t.text3)
                        .textCase(.uppercase)
                        .kerning(1.5)
                    HStack(spacing: 0) {
                        Text("prod-api")
                            .foregroundStyle(t.text)
                        Text("_")
                            .foregroundStyle(t.accent)
                    }
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                }
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .padding(.horizontal, 26)

                // Connected status row
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(.sRGB, red: 0.2, green: 0.8, blue: 0.4, opacity: 1))
                        .frame(width: 7, height: 7)
                    Text("connected — you're in.")
                        .font(.dsMonoPt(12, weight: .bold))
                        .foregroundStyle(Color(.sRGB, red: 0.2, green: 0.8, blue: 0.4, opacity: 1))
                }
                .padding(.horizontal, 26)
                .padding(.top, 12)

                // Body
                Text("Try one of these to feel the two modes — $ runs a command, # talks to the agent:")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 26)
                    .padding(.top, 10)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                // 3 command cards
                VStack(spacing: 8) {
                    commandCard(
                        command: "$ ls -la",
                        description: "list files",
                        highlighted: true
                    )
                    commandCard(
                        command: "# explain this repo",
                        description: "ask the agent",
                        highlighted: false,
                        hashInAccent: true
                    )
                    commandCard(
                        command: "$ npm run dev",
                        description: "start dev server → preview",
                        highlighted: false
                    )
                }
                .padding(.horizontal, 26)
                .padding(.top, 16)

                // Static input bar
                HStack(spacing: 0) {
                    Text("$ command or # ask…")
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text4)
                        .padding(.leading, 14)
                    Spacer()
                }
                .padding(.vertical, 11)
                .background(t.surfaceSunk)
                .overlay(
                    Rectangle()
                        .strokeBorder(t.border, lineWidth: 1)
                )
                .padding(.horizontal, 26)
                .padding(.top, 16)

                // Step dots + CTA
                VStack(spacing: 14) {
                    stepDots
                        .frame(maxWidth: .infinity, alignment: .center)
                    DSButton("get started", variant: .primary, size: .lg, fullWidth: true, action: advance)
                }
                .padding(.horizontal, 26)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func commandCard(command: String, description: String, highlighted: Bool, hashInAccent: Bool = false) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                if hashInAccent, command.hasPrefix("#") {
                    HStack(spacing: 0) {
                        Text("#")
                            .foregroundStyle(t.accent)
                        Text(command.dropFirst())
                            .foregroundStyle(t.text)
                    }
                    .font(.dsMonoPt(13, weight: .bold))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                } else {
                    Text(command)
                        .font(.dsMonoPt(13, weight: .bold))
                        .foregroundStyle(t.text)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                }
                Text(description)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            }
            Spacer()
        }
        .padding(14)
        .background(t.surface)
        .overlay(
            Rectangle()
                .strokeBorder(highlighted ? t.accent : t.border, lineWidth: highlighted ? 1.5 : 0.5)
        )
    }

    // ================================================================
    // MARK: Screen 7 — Managed compute escape hatch
    // ================================================================

    private var screen7Compute: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer(minLength: 40)

                // DotMatrix at center-top
                DotMatrixView(state: .working, cols: 20, rows: 6, cell: 9, dot: 4)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                // Title
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("no server?")
                            .foregroundStyle(t.text)
                    }
                    HStack(spacing: 0) {
                        Text("we'll spin one up")
                            .foregroundStyle(t.text)
                        Text("_")
                            .foregroundStyle(t.accent)
                    }
                }
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .padding(.horizontal, 26)
                .padding(.top, 20)

                // Body
                Text("Launch a managed cloud workspace in ~30s. Pay only for what you use — no subscription to use your own host.")
                    .font(.dsMonoPt(11.5))
                    .foregroundStyle(t.text3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320)
                    .padding(.horizontal, 26)
                    .padding(.top, 14)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                // Chips row
                HStack(spacing: 8) {
                    DSChip("fly.io", tone: .accent, variant: .default)
                    DSChip("4 vCPU", tone: .neutral, variant: .default)
                    DSChip("metered", tone: .neutral, variant: .default)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 26)
                .padding(.top, 20)

                Spacer(minLength: 32)

                // Step dots + CTAs
                VStack(spacing: 14) {
                    stepDots
                        .frame(maxWidth: .infinity, alignment: .center)
                    VStack(spacing: 12) {
                        DSButton("create a workspace", variant: .primary, size: .lg, fullWidth: true) {
                            onSetupWorkspace()
                        }
                        DSButton("i'll use my own host", variant: .ghost, size: .lg, fullWidth: true) {
                            onContinue()
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }
}

// ================================================================
// MARK: - SSH Screen (extracted for @State isolation)
// ================================================================

private struct SSHScreen: View {
    let onContinue: () -> Void
    let currentStep: Int
    @State private var selectedPlatform: SSHPlatform = .macOS
    @State private var copyFeedback = false
    @Environment(\.conduitTokens) private var t

    private var stepDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<OnboardingView.totalSteps, id: \.self) { i in
                Rectangle()
                    .fill(i == currentStep ? t.accent : t.border)
                    .frame(width: i == currentStep ? 16 : 6, height: 4)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 32)

                // Title
                HStack(spacing: 0) {
                    Text("enable ssh")
                        .foregroundStyle(t.text)
                    Text("_")
                        .foregroundStyle(t.accent)
                }
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .padding(.horizontal, 26)

                // Body
                Text("On the machine you want to control:")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .padding(.horizontal, 26)
                    .padding(.top, 10)

                // Segmented platform picker
                DSSegmentedPicker(
                    options: SSHPlatform.allCases.map { (label: $0.rawValue, value: $0) },
                    selection: $selectedPlatform
                )
                .padding(.horizontal, 26)
                .padding(.top, 20)

                // Code block
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(codeLines, id: \.self) { line in
                        Text(line)
                            .font(.dsMonoPt(11.5))
                            .foregroundStyle(line.hasPrefix("#") ? t.text3 : t.text)
                            .padding(.vertical, 2)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(t.surfaceSunk)
                .overlay(
                    Rectangle()
                        .strokeBorder(t.border, lineWidth: 1)
                )
                .padding(.horizontal, 26)
                .padding(.top, 12)
                .animation(.easeInOut(duration: 0.15), value: selectedPlatform)

                // Copy button
                Button {
                    UIPasteboard.general.string = codeLines.joined(separator: "\n")
                    withAnimation { copyFeedback = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { copyFeedback = false }
                    }
                } label: {
                    HStack(spacing: 6) {
                        DSIconView(copyFeedback ? .check : .copy, size: 14, color: copyFeedback ? t.accent : t.text3)
                        Text(copyFeedback ? "copied" : "copy command")
                            .font(.dsMonoPt(12))
                            .foregroundStyle(copyFeedback ? t.accent : t.text3)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(t.surface)
                    .overlay(
                        Rectangle()
                            .strokeBorder(t.border, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 26)
                .padding(.top, 10)

                // "Detected" success chip (static, best-effort feel)
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color(.sRGB, red: 0.2, green: 0.8, blue: 0.4, opacity: 1))
                        .frame(width: 7, height: 7)
                    Text("detected on your network")
                        .font(.dsMonoPt(11, weight: .medium))
                        .foregroundStyle(Color(.sRGB, red: 0.2, green: 0.8, blue: 0.4, opacity: 1))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color(.sRGB, red: 0.2, green: 0.8, blue: 0.4, opacity: 0.1))
                .overlay(
                    Rectangle()
                        .strokeBorder(Color(.sRGB, red: 0.2, green: 0.8, blue: 0.4, opacity: 0.3), lineWidth: 0.5)
                )
                .padding(.horizontal, 26)
                .padding(.top, 12)

                Spacer(minLength: 24)

                VStack(spacing: 14) {
                    stepDots
                        .frame(maxWidth: .infinity, alignment: .center)
                    DSButton("i've enabled it", variant: .primary, size: .lg, fullWidth: true, action: onContinue)
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var codeLines: [String] {
        switch selectedPlatform {
        case .macOS:
            return [
                "# turn on Remote Login",
                "$ sudo systemsetup -setremotelogin on"
            ]
        case .linux:
            return [
                "# Ubuntu/Debian",
                "$ sudo systemctl enable ssh && sudo systemctl start ssh"
            ]
        case .windows:
            return [
                "# PowerShell (as admin)",
                "Add-WindowsCapability -Online -Name OpenSSH.Server"
            ]
        }
    }
}

// ================================================================
// MARK: - Face ID Screen (extracted for @State isolation)
// ================================================================

private struct FaceIDScreen: View {
    let onContinue: () -> Void
    let currentStep: Int
    @Environment(\.conduitTokens) private var t

    private var stepDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<OnboardingView.totalSteps, id: \.self) { i in
                Rectangle()
                    .fill(i == currentStep ? t.accent : t.border)
                    .frame(width: i == currentStep ? 16 : 6, height: 4)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer(minLength: 40)

                // Face ID icon: 64×64 square border with face glyph
                ZStack {
                    Rectangle()
                        .strokeBorder(t.text, lineWidth: 2)
                        .frame(width: 64, height: 64)
                    Image(systemName: "faceid")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(t.text)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                // Title
                HStack(spacing: 0) {
                    Text("lock it down")
                        .foregroundStyle(t.text)
                    Text("_")
                        .foregroundStyle(t.accent)
                }
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .padding(.horizontal, 26)
                .padding(.top, 18)

                // Body
                Text("Require Face ID before approving high-risk actions or opening the app.")
                    .font(.dsMonoPt(11.5))
                    .foregroundStyle(t.text3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300)
                    .padding(.horizontal, 26)
                    .padding(.top, 12)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                Spacer(minLength: 24)

                // Step dots + buttons
                VStack(spacing: 14) {
                    stepDots
                        .frame(maxWidth: .infinity, alignment: .center)
                    DSButton("use face id", variant: .primary, size: .lg, fullWidth: true) {
                        Task {
                            try? await BiometricGate.shared.unlock(reason: "Enable Face ID for approvals")
                            onContinue()
                        }
                    }
                    Button { onContinue() } label: {
                        Text("skip")
                            .font(.dsMonoPt(12))
                            .foregroundStyle(t.text3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }
}

#endif
