#if os(iOS)
import SwiftUI
import DesignSystem
import ConduitCore

// MARK: - Caution level (design's 3 tiers)

/// The onboarding "How cautious?" tiers as shown in the design. Kept separate from
/// `AutonomyPreset` because the design's three labels (Cautious / Balanced / Bypass) don't map
/// 1:1 onto the existing policy enum — `mappedPreset` is the current best-effort bridge.
public enum OnboardingCautionLevel: String, CaseIterable, Identifiable, Sendable {
    case cautious
    case balanced
    case bypass

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cautious: return "Cautious"
        case .balanced: return "Balanced"
        case .bypass:   return "Autonomous"
        }
    }

    public var detail: String {
        switch self {
        case .cautious: return "Approve every action myself"
        case .balanced: return "Auto-approve low-risk, ask the rest"
        case .bypass:   return "Only stop me for high-risk"
        }
    }

    public var recommended: Bool { self == .balanced }

    /// Clean 3-tier mapping onto the policy model (Balanced uses the dedicated `.autoSafeWrites`).
    public var mappedPreset: AutonomyPreset {
        switch self {
        case .cautious: return .autoReads
        case .balanced: return .autoSafeWrites
        case .bypass:   return .agentDecides
        }
    }
}

// MARK: - Leading control (per-step, owner spec)

public enum OnboardingLeadingControl {
    case none      // reserved empty slot (keeps layout stable)
    case back      // ‹ chevron
    case close     // ✕ (e.g. cancel QR scan)
}

// MARK: - Scaffold

/// Consistent onboarding chrome: a fixed top bar (leading control top-left, page dots top-right)
/// + scrollable body + solid footer. EVERY onboarding step renders through this so the chrome
/// never shifts between screens.
public struct OnboardingScaffold<Body: View, Footer: View>: View {
    let stepIndex: Int
    let totalSteps: Int
    let leading: OnboardingLeadingControl
    let onLeading: () -> Void
    @ViewBuilder let content: () -> Body
    @ViewBuilder let footer: () -> Footer

    @Environment(\.conduitTokens) private var t

    public init(
        stepIndex: Int,
        totalSteps: Int,
        leading: OnboardingLeadingControl,
        onLeading: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> Body,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.stepIndex = stepIndex
        self.totalSteps = totalSteps
        self.leading = leading
        self.onLeading = onLeading
        self.content = content
        self.footer = footer
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer()
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            leadingControl
                .frame(width: 38, height: 38, alignment: .leading)   // slot always reserved
            Spacer()
            OnboardingStepDots(total: totalSteps, current: stepIndex)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var leadingControl: some View {
        switch leading {
        case .none:
            Color.clear.frame(width: 38, height: 38)
        case .back:
            Button(action: onLeading) {
                DSIconView(.arrowReturn, size: 17, color: t.text2)
                    .frame(width: 38, height: 38)
                    .background(t.surface)
                    .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        case .close:
            Button(action: onLeading) {
                DSIconView(.close, size: 17, color: t.text2)
                    .frame(width: 38, height: 38)
                    .background(t.surface)
                    .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Step dots (page indicator, top-right)

public struct OnboardingStepDots: View {
    let total: Int
    let current: Int
    @Environment(\.conduitTokens) private var t

    public init(total: Int, current: Int) {
        self.total = total
        self.current = current
    }

    public var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { i in
                Rectangle()
                    .fill(i == current ? t.accent : t.border)
                    .frame(width: i == current ? 16 : 6, height: 4)
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: current)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

// MARK: - Footer container (solid, never a gradient)

/// Standard onboarding footer: 1px top border + the provided CTA content over a solid bg.
public struct OnboardingFooter<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.conduitTokens) private var t

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(t.border).frame(height: 1)
            content()
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 16)
        }
        .background(t.bg.ignoresSafeArea(edges: .bottom))
    }
}
#endif
