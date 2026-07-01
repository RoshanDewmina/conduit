#if os(iOS)
import SwiftUI
import DesignSystem
import LancerCore

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

public enum OnboardingTopBarStyle {
    case page
    case hero
}

// MARK: - Scaffold

/// Consistent onboarding chrome: a fixed top bar (leading control top-left, page dots top-right)
/// + scrollable body + solid footer. EVERY onboarding step renders through this so the chrome
/// never shifts between screens.
public struct OnboardingScaffold<Body: View, Footer: View>: View {
    let stepIndex: Int
    let totalSteps: Int
    let leading: OnboardingLeadingControl
    let topBarStyle: OnboardingTopBarStyle
    let onLeading: () -> Void
    @ViewBuilder let content: () -> Body
    @ViewBuilder let footer: () -> Footer

    @Environment(\.lancerTokens) private var t

    public init(
        stepIndex: Int,
        totalSteps: Int,
        leading: OnboardingLeadingControl,
        topBarStyle: OnboardingTopBarStyle = .page,
        onLeading: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> Body,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.stepIndex = stepIndex
        self.totalSteps = totalSteps
        self.leading = leading
        self.topBarStyle = topBarStyle
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
        .background {
            if topBarStyle == .hero {
                OnboardingHeroBackground(clippedBottomCorners: false)
                    .ignoresSafeArea(edges: .top)
            }
        }
    }

    @ViewBuilder
    private var leadingControl: some View {
        switch leading {
        case .none:
            Color.clear.frame(width: 38, height: 38)
        case .back:
            Button(action: onLeading) {
                DSIconView(.chevronLeft, size: 17, color: t.text2)
                    .frame(width: 38, height: 38)
            }
            .lancerGlassCircle(fallbackSurface: t.surface)
            .accessibilityLabel("Back")
        case .close:
            Button(action: onLeading) {
                DSIconView(.close, size: 17, color: t.text2)
                    .frame(width: 38, height: 38)
            }
            .lancerGlassCircle(fallbackSurface: t.surface)
            .accessibilityLabel("Close")
        }
    }
}

// MARK: - Step dots (page indicator, top-right)

public struct OnboardingStepDots: View {
    let total: Int
    let current: Int
    @Environment(\.lancerTokens) private var t

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
    @Environment(\.lancerTokens) private var t

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

// MARK: - Hero banner (shared branded header — content, not chrome)

/// The orange/terracotta gradient branded header, extracted so the same visual identity
/// (brand mark, eyebrow, title, body) persists on every onboarding screen instead of
/// degrading to a flat background once you leave the value/pair/policy carousel. This is
/// content rendered inside `OnboardingScaffold`'s `content` slot, NOT chrome — the back
/// chevron and step dots live in the scaffold itself, once, so they never duplicate or drift.
public struct OnboardingHeroBanner: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let compact: Bool

    @Environment(\.lancerTokens) private var t

    public init(eyebrow: String, title: String, subtitle: String, compact: Bool = false) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.compact = compact
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingBrandMark()
                .scaleEffect(compact ? 0.68 : 1)
                .frame(width: compact ? 38 : 56, height: compact ? 38 : 56)
                .padding(.bottom, compact ? 8 : 18)
            Text(eyebrow)
                .font(.dsEditorialPt(20))
                .foregroundStyle(OnboardingHeroPalette.heroKicker)
            Text(title)
                .font(.dsDisplayPt(compact ? 26 : 34, weight: .heavy))
                .tracking(-1)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
            Text(subtitle)
                .font(.dsSansPt(13))
                .lineSpacing(3)
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 292, alignment: .leading)
                .padding(.top, compact ? 6 : 12)
        }
        .padding(.horizontal, 28)
        .padding(.top, compact ? 8 : 22)
        .padding(.bottom, compact ? 12 : 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OnboardingHeroBackground(clippedBottomCorners: true).ignoresSafeArea(edges: .top))
    }
}

private struct OnboardingHeroBackground: View {
    let clippedBottomCorners: Bool
    @Environment(\.lancerTokens) private var t

    var body: some View {
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
        .clipShape(
            clippedBottomCorners
            ? UnevenRoundedRectangle(bottomLeadingRadius: 34, bottomTrailingRadius: 34, style: .continuous)
            : UnevenRoundedRectangle(style: .continuous)
        )
    }
}

private enum OnboardingHeroPalette {
    /// Peach kicker used over the terracotta hero (`heroKicker` #F6D8C5).
    static let heroKicker = Color(.sRGB, red: 0.965, green: 0.847, blue: 0.773, opacity: 1)
}

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
#endif
