#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit
import ConduitCore
import SSHTransport

// MARK: - SSH platform enum (shared)

private enum SSHPlatform: String, CaseIterable, Identifiable {
    case macOS   = "macOS"
    case linux   = "Linux"
    case windows = "Windows"
    var id: String { rawValue }
}

// MARK: - OnboardingView (public — BLOCKS dark, 4 screens)

/// Dark onboarding walkthrough. 4 screens: hero → connect host → caution preset → done.
/// Notifications, Face ID, and session coaching are deferred to contextual prompts.
public struct OnboardingView: View {
    public let onContinue: () -> Void
    public let onAlreadyUseConduit: () -> Void
    public let onSetupWorkspace: () -> Void
    public let relayClient: E2ERelayClient?

    @State private var step: Int = 0
    @State private var animationDirection: Int = 1
    @State private var selectedPreset: AutonomyPreset = .autoReads
    @State private var showPairing = false
    @Environment(\.conduitTokens) private var t

    fileprivate static let totalSteps = 4

    public init(
        onContinue: @escaping () -> Void,
        onAlreadyUseConduit: @escaping () -> Void = {},
        onSetupWorkspace: @escaping () -> Void = {},
        relayClient: E2ERelayClient? = nil
    ) {
        self.onContinue = onContinue
        self.onAlreadyUseConduit = onAlreadyUseConduit
        self.onSetupWorkspace = onSetupWorkspace
        self.relayClient = relayClient
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                scrollContent
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

                ctaFooter
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
        .sheet(isPresented: $showPairing) {
            BridgePairingView(
                client: relayClient,
                onUseSSH: { showPairing = false },
                onPaired: { _, _ in
                    showPairing = false
                    onContinue()
                }
            )
        }
    }

    // MARK: Scroll content switcher

    @ViewBuilder
    private var scrollContent: some View {
        switch step {
        case 0:  screen1Welcome.id("s0")
        case 1:  screen2SSH.id("s1")
        case 2:  screen3Preset.id("s2")
        default: screen4Compute.id("s3")
        }
    }

    // MARK: Solid footer CTA (R1.1 — never a gradient)

    private var ctaFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(t.border)
                .frame(height: 1)

            ctaButtons
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 16)
        }
        .background(t.bg.ignoresSafeArea(edges: .bottom))
    }

    @ViewBuilder
    private var ctaButtons: some View {
        switch step {
        case 0:
            VStack(spacing: 10) {
                DSButton("get started", variant: .primary, size: .lg, fullWidth: true, action: advance)
                Button {
                    onAlreadyUseConduit()
                } label: {
                    Text("i already use conduit")
                        .font(.dsMonoPt(13))
                        .foregroundStyle(t.text3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }

        case 1:
            DSButton("i've enabled ssh", variant: .primary, size: .lg, fullWidth: true, action: advance)

        case 2:
            HStack(spacing: 10) {
                stepDots
                Spacer()
                DSButton("continue", variant: .primary, size: .md, action: advance)
            }

        default:
            HStack(spacing: 10) {
                DSButton("use my own host", variant: .ghost, size: .lg, fullWidth: true) {
                    onContinue()
                }
                DSButton("create workspace", variant: .primary, size: .lg, fullWidth: true) {
                    onSetupWorkspace()
                }
            }
        }
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
    // MARK: Screen 1 — Hero (Welcome)
    // ================================================================

    private var screen1Welcome: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                SpectrumBar(mode: .working, height: 10)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)

                Text("conduit")
                    .font(.dsMonoPt(10, weight: .bold))
                    .foregroundStyle(t.text3)
                    .kerning(2.5)
                    .textCase(.uppercase)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("agents ask.")
                        .foregroundStyle(t.text)
                    Text("you approve.")
                        .foregroundStyle(t.text3)
                    Text("work resumes.")
                        .foregroundStyle(t.accent)
                }
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .lineSpacing(0)
                .tracking(0)
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                Text("Coding agents pause for risky actions. Conduit sends the approval to your phone, then safely resumes the run.")
                    .font(.dsSansPt(15))
                    .foregroundStyle(t.text3)
                    .lineSpacing(6)
                    .frame(maxWidth: 300, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // ================================================================
    // MARK: Screen 2 — Connect host (SSH + bridge)
    // ================================================================

    private var screen2SSH: some View {
        SSHScreen(showPairing: $showPairing)
    }

    // ================================================================
    // MARK: Screen 3 — Caution preset
    // ================================================================

    private var screen3Preset: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 32)

                HStack(spacing: 0) {
                    Text("approval policy")
                        .foregroundStyle(t.text)
                    Text("_")
                        .foregroundStyle(t.accent)
                }
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .padding(.horizontal, 18)

                Text("How much should the agent pause and ask? You can change this per-session later.")
                    .font(.dsSansPt(14.5))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                VStack(spacing: 8) {
                    ForEach(AutonomyPreset.allCases, id: \.self) { preset in
                        presetRow(preset)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func presetRow(_ preset: AutonomyPreset) -> some View {
        let selected = selectedPreset == preset
        return Button {
            withAnimation(.easeInOut(duration: 0.12)) { selectedPreset = preset }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Rectangle()
                    .fill(selected ? t.accent : t.border)
                    .frame(width: 3)
                    .frame(height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.label)
                        .font(.dsMonoPt(13, weight: .bold))
                        .foregroundStyle(selected ? t.text : t.text2)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                    Text(preset.description)
                        .font(.dsSansPt(13))
                        .foregroundStyle(t.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                }
                .padding(.vertical, 12)

                Spacer()
            }
            .padding(.horizontal, 14)
            .background(selected ? t.surface : Color.clear)
            .overlay(
                Rectangle()
                    .strokeBorder(selected ? t.borderStrong : t.border, lineWidth: selected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // ================================================================
    // MARK: Screen 4 — Done / compute escape hatch
    // ================================================================

    private var screen4Compute: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer(minLength: 40)

                DotMatrixView(state: .working, cols: 20, rows: 6, cell: 9, dot: 4)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

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
                .padding(.horizontal, 18)
                .padding(.top, 20)

                Text("Launch a managed cloud workspace in ~30s. Pay only for what you use — no subscription to use your own host.")
                    .font(.dsSansPt(14.5))
                    .foregroundStyle(t.text3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                HStack(spacing: 8) {
                    DSChip("fly.io", tone: .accent, variant: .default)
                    DSChip("4 vCPU", tone: .neutral, variant: .default)
                    DSChip("metered", tone: .neutral, variant: .default)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 24)
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
    @State private var selectedPlatform: SSHPlatform = .macOS
    @State private var copyFeedback = false
    @Binding var showPairing: Bool
    @Environment(\.conduitTokens) private var t

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 32)

                HStack(spacing: 0) {
                    Text("connect a host")
                        .foregroundStyle(t.text)
                    Text("_")
                        .foregroundStyle(t.accent)
                }
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .padding(.horizontal, 18)

                Text("Connecting installs the bridge (conduitd) that enforces your policy and survives disconnects. Enable SSH on the machine you want to control:")
                    .font(.dsSansPt(14.5))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                Button {
                    showPairing = true
                } label: {
                    HStack(spacing: 10) {
                        DSIconView(.plus, size: 15, color: t.accent)
                        Text("Pair the bridge")
                            .font(.dsMonoPt(13))
                            .foregroundStyle(t.text)
                        Spacer()
                        DSIconView(.chevronRight, size: 15, color: t.text3)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(t.surface)
                    .overlay(
                        Rectangle()
                            .strokeBorder(t.borderStrong, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.bottom, 16)

                DSSegmentedPicker(
                    options: SSHPlatform.allCases.map { (label: $0.rawValue, value: $0) },
                    selection: $selectedPlatform
                )
                .padding(.horizontal, 18)

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
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .animation(.easeInOut(duration: 0.15), value: selectedPlatform)

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
                .padding(.horizontal, 18)
                .padding(.top, 10)

                HStack(spacing: 7) {
                    DSIconView(.key, size: 13, color: t.accent)
                    Text("First connect asks you to trust the host key. Passwords and keys stay in Keychain.")
                        .font(.dsMonoPt(11, weight: .medium))
                        .foregroundStyle(t.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(t.accentSoft)
                .overlay(
                    Rectangle().strokeBorder(t.border, lineWidth: 0.5)
                )
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 24)
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

#endif
