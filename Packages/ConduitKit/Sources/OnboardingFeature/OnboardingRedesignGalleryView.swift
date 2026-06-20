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
///
/// Visuals are a faithful reproduction of the `Conduit App.dc.html` onboarding board:
/// a terracotta editorial hero (grid texture + lavender pixel mark, Instrument Serif
/// italic kicker over a Bricolage display title), then a per-step block — value rows,
/// pairing digit-boxes, or policy cards — with a black/orange CTA and an always-present
/// "I've already set up Conduit" link.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            hero
            ScrollView(.vertical, showsIndicators: false) {
                primaryBlock
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: Hero (terracotta editorial header — shared across steps)

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.horizontal, 26)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 0) {
                OnboardingBrandMark()
                    .padding(.bottom, 18)
                Text(current.eyebrow)
                    .font(.dsEditorialPt(20))
                    .foregroundStyle(OnboardingPalette.heroKicker)
                Text(current.title)
                    .font(.dsDisplayPt(34, weight: .heavy))
                    .tracking(-1)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
                Text(current.body)
                    .font(.dsSansPt(13))
                    .lineSpacing(3)
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 292, alignment: .leading)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
        }
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroBackground.ignoresSafeArea(edges: .top))
    }

    private var heroBackground: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: [t.accent, t.accentInk], startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { ctx, size in
                var y: CGFloat = 0
                while y <= size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                             with: .color(.white.opacity(0.05)))
                    y += 30
                }
            }
            Circle()
                .fill(.white.opacity(0.07))
                .frame(width: 190, height: 190)
                .offset(x: 34, y: 46)
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 34, bottomTrailingRadius: 34, style: .continuous))
    }

    private var headerRow: some View {
        HStack(spacing: 9) {
            Button {
                guard step > 0 else { return }
                withAnimation(ConduitMotion.resolved(.smooth(duration: 0.28, extraBounce: 0), reduceMotion: reduceMotion)) { step -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)
            .opacity(step > 0 ? 1 : 0)
            .disabled(step == 0)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("onboardingBack")

            ForEach(0..<steps.count, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(i <= step ? Color.white : Color.white.opacity(0.4))
                    .frame(width: i == step ? 22 : 7, height: 7)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: step)
            }

            Spacer(minLength: 0)

            Button("Skip") { onAlreadyUseConduit() }
                .font(.dsMonoPt(12, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .accessibilityIdentifier("onboardingSkip")
        }
        .frame(height: 20)
    }

    // MARK: Per-step primary block

    @ViewBuilder
    private var primaryBlock: some View {
        switch current.kind {
        case .value:
            OnboardingValueRows().padding(.horizontal, 28).padding(.top, 12)
        case .pair:
            OnboardingPairingBlock(client: client, pairingCode: pairingCode)
                .padding(.horizontal, 24)
        case .policy:
            OnboardingPolicyCards(selectedLevel: $selectedLevel).padding(.horizontal, 24)
        }
    }

    // MARK: Footer CTA

    private var footer: some View {
        VStack(spacing: 11) {
            Button { advanceOrFinish() } label: {
                HStack(spacing: 8) {
                    Text(current.primaryAction)
                    if current.ctaArrow { Text("→") }
                }
                .font(.dsDisplayPt(16, weight: .bold))
                .foregroundStyle(current.kind == .value ? Color.white : t.accentFg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(current.kind == .value ? t.text : t.accent)
                )
                .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 10)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboardingPrimary")

            Button("I've already set up Conduit") { onAlreadyUseConduit() }
                .font(.dsSansPt(14, weight: .semibold))
                .foregroundStyle(t.text3)
                .accessibilityIdentifier("onboardingAlreadySetUp")
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background(t.bg.ignoresSafeArea(edges: .bottom))
    }

    // MARK: Actions

    private func advanceOrFinish() {
        if step < steps.count - 1 {
            Haptics.selection()
            withAnimation(ConduitMotion.resolved(.smooth(duration: 0.28, extraBounce: 0), reduceMotion: reduceMotion)) { step += 1 }
        } else {
            finish()
        }
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
        Haptics.success()
        onContinue()
    }
}

// MARK: - Shared palette (board sand-theme literals not in the semantic token set)

private enum OnboardingPalette {
    /// Peach kicker used over the terracotta hero (`heroKicker` #F6D8C5).
    static let heroKicker = Color(.sRGB, red: 0.965, green: 0.847, blue: 0.773, opacity: 1)
}

// MARK: - Lavender pixel brand-mark

private struct OnboardingBrandMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                AngularGradient(
                    colors: [
                        Color(.sRGB, red: 0.545, green: 0.435, blue: 0.690, opacity: 1), // #8b6fb0
                        Color(.sRGB, red: 0.690, green: 0.561, blue: 0.808, opacity: 1), // #b08fce
                        Color(.sRGB, red: 0.435, green: 0.353, blue: 0.588, opacity: 1), // #6f5a96
                        Color(.sRGB, red: 0.616, green: 0.498, blue: 0.753, opacity: 1), // #9d7fc0
                        Color(.sRGB, red: 0.545, green: 0.435, blue: 0.690, opacity: 1)
                    ],
                    center: .center,
                    angle: .degrees(45)
                )
            )
            .overlay(
                Canvas { ctx, size in
                    var x: CGFloat = 0
                    while x <= size.width { ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.black.opacity(0.12))); x += 11 }
                    var y: CGFloat = 0
                    while y <= size.height { ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.12))); y += 11 }
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.85), lineWidth: 2))
            .frame(width: 56, height: 56)
            .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 8)
            .accessibilityHidden(true)
    }
}

// MARK: - Step 0 · value rows

private struct OnboardingValueRows: View {
    @Environment(\.conduitTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            row(title: "Approve actions from afar", detail: "Allow or deny risky steps in a tap") {
                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(t.accent)
            }
            row(title: "Watch the terminal stream live", detail: "Every command, as it runs") {
                Text("›_").font(.dsMonoPt(15, weight: .semibold)).foregroundStyle(t.accent)
            }
            row(title: "Policy guardrails per host", detail: "Rules enforce on every machine") {
                Image(systemName: "shield.fill").font(.system(size: 15)).foregroundStyle(t.accent)
            }
        }
    }

    private func row<Icon: View>(title: String, detail: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 15) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(t.surface2)
                .frame(width: 44, height: 44)
                .overlay(icon())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.dsSansPt(15, weight: .semibold)).foregroundStyle(t.text)
                Text(detail).font(.dsSansPt(12.5)).foregroundStyle(t.text4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Step 1 · pairing

private struct OnboardingPairingBlock: View {
    @ObservedObject var client: E2ERelayClient
    let pairingCode: String

    @Environment(\.conduitTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ENTER PAIRING CODE")
                .font(.dsMonoPt(10, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(t.text4)
                .padding(.leading, 4)
                .padding(.bottom, 14)

            HStack(spacing: 9) {
                ForEach(0..<6, id: \.self) { i in
                    let digit = digitAt(i)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(t.surface)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(i == firstEmptyIndex ? t.accent : t.border, lineWidth: 1.5)
                        )
                        .overlay(
                            Text(digit)
                                .font(.dsDisplayPt(26, weight: .bold))
                                .foregroundStyle(t.text)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pairing code")
            .accessibilityValue(pairingCode)
            .accessibilityIdentifier("pairingCode")

            HStack(spacing: 4) {
                Text("or")
                Text("scan the QR on your desktop").foregroundStyle(t.accent).fontWeight(.semibold)
            }
            .font(.dsSansPt(13))
            .foregroundStyle(t.text4)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 18)

            Text(statusLabel)
                .font(.dsSansPt(12))
                .foregroundStyle(isPaired ? t.accent : t.text4)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
        }
        .onChange(of: client.pairingState) { _, state in
            switch state {
            case .paired:        Haptics.success()
            case .pairingFailed: Haptics.error()
            case .unpaired, .waitingForPeer: break
            }
        }
    }

    private func digitAt(_ i: Int) -> String {
        guard i < pairingCode.count else { return "" }
        let idx = pairingCode.index(pairingCode.startIndex, offsetBy: i)
        return String(pairingCode[idx])
    }

    private var firstEmptyIndex: Int { pairingCode.count < 6 ? pairingCode.count : -1 }
    private var isPaired: Bool { client.pairingState == .paired }

    private var statusLabel: String {
        switch client.pairingState {
        case .unpaired, .waitingForPeer: return "Waiting for the host to pair…"
        case .paired:                    return "Paired ✓"
        case .pairingFailed:             return "Pairing failed — tap back to retry"
        }
    }
}

// MARK: - Step 2 · policy cards

private struct OnboardingPolicyCards: View {
    @Binding var selectedLevel: OnboardingCautionLevel

    @Environment(\.conduitTokens) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 11) {
            ForEach(OnboardingCautionLevel.allCases) { level in
                let isSelected = selectedLevel == level
                Button {
                    Haptics.selection()
                    withAnimation(ConduitMotion.resolved(.smooth(duration: 0.18, extraBounce: 0), reduceMotion: reduceMotion)) {
                        selectedLevel = level
                    }
                } label: {
                    HStack(spacing: 13) {
                        ZStack {
                            Circle()
                                .strokeBorder(isSelected ? t.accent : t.borderStrong, lineWidth: 2)
                                .frame(width: 24, height: 24)
                            Circle()
                                .fill(isSelected ? t.accent : .clear)
                                .frame(width: 9, height: 9)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(level.title).font(.dsDisplayPt(16, weight: .bold)).foregroundStyle(t.text)
                            Text(level.detail).font(.dsSansPt(12.5)).foregroundStyle(t.text4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(t.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isSelected ? t.accent : t.border, lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(isSelected ? 0.16 : 0.05), radius: isSelected ? 14 : 3, x: 0, y: isSelected ? 6 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("policyPreset_\(level.rawValue)")
                .accessibilityValue(isSelected ? "selected" : "unselected")
            }
        }
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

// MARK: - Step model

private struct OnboardingRedesignStep: Identifiable {
    enum Kind { case value, pair, policy }

    let id: String
    let eyebrow: String
    let title: String
    let body: String
    let primaryAction: String
    let ctaArrow: Bool
    let kind: Kind

    static let all: [OnboardingRedesignStep] = [
        .init(
            id: "value",
            eyebrow: "your machines,",
            title: "in your pocket.",
            body: "Conduit is mission control for the coding agents running on your own machines. Here's what you get:",
            primaryAction: "Connect a machine",
            ctaArrow: true,
            kind: .value
        ),
        .init(
            id: "pair",
            eyebrow: "step one",
            title: "Pair the bridge.",
            body: "End-to-end encrypted — your code never leaves your machines.",
            primaryAction: "Pair & continue",
            ctaArrow: false,
            kind: .pair
        ),
        .init(
            id: "policy",
            eyebrow: "last thing",
            title: "How much rope?",
            body: "Set how freely agents act. You can fine-tune this per host later.",
            primaryAction: "Enter Conduit",
            ctaArrow: true,
            kind: .policy
        ),
    ]
}

#Preview("Onboarding redesign gallery") {
    OnboardingRedesignGalleryView()
        .environment(\.conduitTokens, .light)
}
#endif
