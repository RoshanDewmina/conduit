#if os(iOS)
import SwiftUI
import DesignSystem

public struct OnboardingRedesignGalleryView: View {
    @State private var step = 0
    @State private var selectedPreset: RedesignPolicyPreset = .balanced

    @Environment(\.conduitTokens) private var t

    private let steps = OnboardingRedesignStep.all

    public init() {}

    public var body: some View {
        ConduitOnboardingVariant(
            step: $step,
            selectedPreset: $selectedPreset,
            steps: steps
        )
        .background(t.bg)
    }
}

private struct ConduitOnboardingVariant: View {
    @Binding var step: Int
    @Binding var selectedPreset: RedesignPolicyPreset

    let steps: [OnboardingRedesignStep]

    @Environment(\.conduitTokens) private var t

    var body: some View {
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
    }

    private var current: OnboardingRedesignStep { steps[step] }

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
            ConduitPairingCard()
        case .policy:
            ConduitPolicyCard(selectedPreset: $selectedPreset)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(t.border)
                .frame(height: 0.5)
            VStack(spacing: 10) {
                DSButton(current.primaryAction, variant: .primary, size: .lg, fullWidth: true) {
                    advance()
                }
                if let secondary = current.secondaryAction {
                    Button(secondary) {}
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

    private func advance() {
        guard step < steps.count - 1 else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) { step += 1 }
    }
}

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
    @Environment(\.conduitTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                DSChip("bridge", icon: .server, tone: .accent, variant: .soft, size: .sm)
                DSChip("no account", icon: .shield, tone: .ok, variant: .soft, size: .sm)
                Spacer(minLength: 0)
            }

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
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    Text("482 917")
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .foregroundStyle(t.text)
                    Text("Auto-pairs after install.")
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.text3)
                }
            }
        }
        .padding(16)
        .background(t.surface)
        .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
    }
}

private struct ConduitPolicyCard: View {
    @Binding var selectedPreset: RedesignPolicyPreset

    @Environment(\.conduitTokens) private var t

    var body: some View {
        VStack(spacing: 8) {
            ForEach(RedesignPolicyPreset.allCases) { preset in
                Button {
                    withAnimation(.easeInOut(duration: 0.14)) { selectedPreset = preset }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        DSStatusDot(tone: selectedPreset == preset ? .accent : .off, size: 9)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(preset.title)
                                    .font(.dsSansPt(15, weight: .semibold))
                                    .foregroundStyle(t.text)
                                if preset == .balanced {
                                    DSChip("recommended", tone: .accent, variant: .soft, size: .sm)
                                }
                            }
                            Text(preset.detail)
                                .font(.dsSansPt(13))
                                .foregroundStyle(t.text3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selectedPreset == preset ? t.accentSoft : t.surface)
                    .overlay(
                        Rectangle()
                            .strokeBorder(selectedPreset == preset ? t.accent : t.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

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

private enum RedesignPolicyPreset: String, CaseIterable, Identifiable {
    case cautious
    case balanced
    case bypass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cautious: return "Cautious"
        case .balanced: return "Balanced"
        case .bypass: return "Bypass"
        }
    }

    var detail: String {
        switch self {
        case .cautious:
            return "Ask on every write, network call, secret, and destructive action."
        case .balanced:
            return "Auto-allow safe reads and routine writes; ask on risky actions."
        case .bypass:
            return "Ask only for critical actions in trusted repositories."
        }
    }
}

#Preview("Onboarding redesign gallery") {
    OnboardingRedesignGalleryView()
        .environment(\.conduitTokens, .dark)
}
#endif
