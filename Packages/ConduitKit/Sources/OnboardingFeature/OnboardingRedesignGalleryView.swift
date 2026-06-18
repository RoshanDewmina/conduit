#if os(iOS)
import SwiftUI
import DesignSystem
import ConduitCore
import SecurityKit
import SSHTransport

// MARK: - OnboardingRedesignView (productized 3-step first-run)

/// First-run onboarding in the simplified 3-step language: Why Conduit → Pair the
/// bridge → Default policy. Pairing is real (drives the app-wide `E2ERelayClient`
/// with a real 6-digit code); the chosen policy tier is persisted and pushed to the
/// daemon on first connect via `OnboardingPolicy`.
public struct OnboardingRedesignView: View {
    let onContinue: () -> Void
    let onAlreadyUseConduit: () -> Void
    let onSetupWorkspace: () -> Void

    @StateObject private var client: E2ERelayClient
    @State private var step: Int
    @State private var selectedLevel: OnboardingCautionLevel = .balanced
    @State private var pairingCode = ""
    @State private var didStartPairing = false

    @AppStorage("conduit.onboarding.autonomyPreset") private var storedPreset: String = ""
    @Environment(\.conduitTokens) private var t

    private let steps = OnboardingRedesignStep.all

    public init(
        onContinue: @escaping () -> Void,
        onAlreadyUseConduit: @escaping () -> Void = {},
        onSetupWorkspace: @escaping () -> Void = {},
        relayClient: E2ERelayClient? = nil,
        startStep: Int = 0
    ) {
        self.onContinue = onContinue
        self.onAlreadyUseConduit = onAlreadyUseConduit
        self.onSetupWorkspace = onSetupWorkspace
        let resolved = relayClient ?? E2ERelayClient(
            relayURL: RelaySettings.url(),
            pairingCode: PairingCrypto.generatePairingCode()
        )
        _client = StateObject(wrappedValue: resolved)
        _step = State(initialValue: min(max(startStep, 0), OnboardingRedesignStep.all.count - 1))
    }

    private var current: OnboardingRedesignStep { steps[step] }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    headline
                    primaryBlock
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            footer
        }
        .background(t.bg.ignoresSafeArea())
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .onChange(of: step) { _, new in
            if steps[new].kind == .pair { startPairingIfNeeded() }
        }
        .onAppear { if current.kind == .pair { startPairingIfNeeded() } }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    guard step > 0 else { return }
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) { step -= 1 }
                } label: {
                    DSIconView(.arrowReturn, size: 17, color: step > 0 ? t.text2 : t.text4)
                        .frame(width: 38, height: 38)
                        .background(t.surface)
                        .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(step == 0)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("onboardingBack")

                VStack(alignment: .leading, spacing: 5) {
                    Text("CONDUIT SETUP")
                        .font(.dsMonoPt(10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(t.text3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    DSProgressSegmented(total: steps.count, done: step, active: step)
                }

                Spacer()

                Text("\(step + 1) / \(steps.count)")
                    .font(.dsMonoPt(12, weight: .medium))
                    .foregroundStyle(t.text3)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 6)
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(current.eyebrow)
                .font(.dsMonoPt(11, weight: .medium))
                .tracking(1.1)
                .foregroundStyle(t.accent)
                .textCase(.uppercase)

            Text(current.title)
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .foregroundStyle(t.text)
                .tracking(0)
                .lineLimit(3)
                .minimumScaleFactor(0.84)
                .fixedSize(horizontal: false, vertical: true)

            Text(current.body)
                .font(.dsSansPt(15))
                .foregroundStyle(t.text2)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360, alignment: .leading)
        }
    }

    @ViewBuilder
    private var primaryBlock: some View {
        switch current.kind {
        case .value:
            ConduitLoopCard()
        case .pair:
            ConduitPairingCard(client: client, pairingCode: pairingCode)
        case .policy:
            ConduitPolicyCard(selectedLevel: $selectedLevel)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(t.border)
                .frame(height: 0.5)
            VStack(spacing: 10) {
                DSButton(current.primaryAction, variant: .primary, size: .lg, fullWidth: true) {
                    advanceOrFinish()
                }
                if let secondary = current.secondaryAction {
                    Button(secondary) { handleSecondary() }
                        .font(.dsMonoPt(12, weight: .medium))
                        .foregroundStyle(t.text3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .background(t.bg.ignoresSafeArea(edges: .bottom))
    }

    // MARK: Actions

    private func advanceOrFinish() {
        if step < steps.count - 1 {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) { step += 1 }
        } else {
            finish()
        }
    }

    private func handleSecondary() {
        // The only secondary action is "I already use Conduit" on the value step.
        if current.kind == .value { onAlreadyUseConduit() }
    }

    private func startPairingIfNeeded() {
        guard !didStartPairing else { return }
        didStartPairing = true
        let code = client.beginPairingSession()
        pairingCode = code
        client.relayURL = RelaySettings.url()
        client.connect()
    }

    private func finish() {
        storedPreset = selectedLevel.mappedPreset.rawValue
        // Push this tier's starter policy on the first daemon connect (see OnboardingPolicy).
        OnboardingPolicy.markPending(selectedLevel)
        onContinue()
    }
}

// MARK: - Gallery wrapper (DebugGalleryView route `onboarding-redesign`)

/// Visual-reference + XCUITest entry point. Renders the productized view with
/// no-op callbacks so the flow can be walked without leaving the gallery.
public struct OnboardingRedesignGalleryView: View {
    let startStep: Int
    @Environment(\.conduitTokens) private var t
    public init(startStep: Int = 0) { self.startStep = startStep }
    public var body: some View {
        OnboardingRedesignView(onContinue: {}, onSetupWorkspace: {}, startStep: startStep)
            .background(t.bg)
    }
}

// MARK: - Cards

private struct ConduitLoopCard: View {
    @Environment(\.conduitTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            loopRow(number: "01", title: "Agent pauses", detail: "A risky command, file write, or question stops the run.")
            divider
            loopRow(number: "02", title: "You decide", detail: "Approve, deny, edit, or make a scoped rule from your phone.")
            divider
            loopRow(number: "03", title: "Work resumes", detail: "The host keeps running with the policy you chose.")
        }
        .padding(16)
        .background(t.surface)
        .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
    }

    private var divider: some View {
        Rectangle()
            .fill(t.border)
            .frame(height: 0.5)
    }

    private func loopRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.dsMonoPt(11, weight: .bold))
                .foregroundStyle(t.accent)
                .frame(width: 30, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.dsSansPt(15, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(detail)
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ConduitPairingCard: View {
    @ObservedObject var client: E2ERelayClient
    let pairingCode: String

    @Environment(\.conduitTokens) private var t
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("$ curl -fsSL conduit.dev/install | sh")
                        .font(.dsMonoPt(13))
                        .foregroundStyle(t.text)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Installs conduitd, then pairs this phone to the host.")
                        .font(.dsSansPt(13))
                        .foregroundStyle(t.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    UIPasteboard.general.string = "curl -fsSL conduit.dev/install | sh"
                    didCopy = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        didCopy = false
                    }
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(t.text3)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .top)
            .background(t.surfaceSunk)
            .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))

            HStack(spacing: 14) {
                DotMatrixView(state: .working, cols: 7, rows: 7, cell: 6, dot: 3)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("PAIRING CODE")
                        .font(.dsMonoPt(9, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(t.text3)
                    Text(displayCode)
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .foregroundStyle(t.text)
                        .accessibilityIdentifier("pairingCode")
                    Text(statusLabel)
                        .font(.dsSansPt(12))
                        .foregroundStyle(isPaired ? t.accent : t.text3)
                }
            }
        }
        .padding(16)
        .background(t.surface)
        .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
    }

    private var isPaired: Bool { client.pairingState == .paired }

    private var displayCode: String {
        let digits = pairingCode
        guard digits.count == 6 else { return digits.isEmpty ? "— — —" : digits }
        let mid = digits.index(digits.startIndex, offsetBy: 3)
        return "\(digits[..<mid]) \(digits[mid...])"
    }

    private var statusLabel: String {
        switch client.pairingState {
        case .unpaired, .waitingForPeer: return "Waiting for the host to pair…"
        case .paired:                    return "Paired ✓"
        case .pairingFailed:             return "Pairing failed — tap back to retry"
        }
    }
}

private struct ConduitPolicyCard: View {
    @Binding var selectedLevel: OnboardingCautionLevel

    @Environment(\.conduitTokens) private var t

    var body: some View {
        VStack(spacing: 8) {
            ForEach(OnboardingCautionLevel.allCases) { level in
                Button {
                    withAnimation(.easeInOut(duration: 0.14)) { selectedLevel = level }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        DSStatusDot(tone: selectedLevel == level ? .accent : .off, size: 9)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(level.title)
                                    .font(.dsSansPt(15, weight: .semibold))
                                    .foregroundStyle(t.text)
                                if level.recommended {
                                    DSChip("recommended", tone: .accent, variant: .soft, size: .sm)
                                }
                            }
                            Text(level.detail)
                                .font(.dsSansPt(13))
                                .foregroundStyle(t.text3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selectedLevel == level ? t.accentSoft : t.surface)
                    .overlay(
                        Rectangle()
                            .strokeBorder(selectedLevel == level ? t.accent : t.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("policyPreset_\(level.rawValue)")
                .accessibilityValue(selectedLevel == level ? "selected" : "unselected")
            }
        }
    }
}

// MARK: - Step model

private struct OnboardingRedesignStep: Identifiable {
    enum Kind {
        case value
        case pair
        case policy
    }

    let id: String
    let eyebrow: String
    let title: String
    let body: String
    let primaryAction: String
    let secondaryAction: String?
    let kind: Kind

    static let all: [OnboardingRedesignStep] = [
        .init(
            id: "value",
            eyebrow: "Why Conduit",
            title: "Agents ask. You approve. Work resumes.",
            body: "Conduit puts risky agent actions on your phone so you can keep work moving without opening the terminal.",
            primaryAction: "Get started",
            secondaryAction: nil,
            kind: .value
        ),
        .init(
            id: "pair",
            eyebrow: "Pair the bridge",
            title: "Connect the machine where agents run.",
            body: "Install the local bridge once. It enforces policy, sends approval requests, and keeps your host reachable.",
            primaryAction: "Continue",
            secondaryAction: nil,
            kind: .pair
        ),
        .init(
            id: "policy",
            eyebrow: "Default policy",
            title: "Choose how cautious Conduit should be.",
            body: "Start balanced. You can tighten or loosen individual rules later from Settings.",
            primaryAction: "Connect and finish",
            secondaryAction: nil,
            kind: .policy
        ),
    ]
}

#Preview("Onboarding redesign gallery") {
    OnboardingRedesignGalleryView()
        .environment(\.conduitTokens, .dark)
}
#endif
