import SwiftUI

public enum LancerMotion {
    public static let navigation = Animation.smooth(duration: 0.36, extraBounce: 0)
    public static let emphasis = Animation.snappy(duration: 0.22, extraBounce: 0)

    public static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

public extension View {
    /// Applies the shared motion policy without forcing decorative movement when
    /// the person has requested reduced motion.
    func lancerMotion<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(LancerMotionModifier(animation: animation, value: value))
    }
}

private struct LancerMotionModifier<Value: Equatable>: ViewModifier {
    let animation: Animation
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(LancerMotion.resolved(animation, reduceMotion: reduceMotion), value: value)
    }
}

public struct LancerPage<Content: View>: View {
    private let content: Content

    @Environment(\.lancerTokens) private var t

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(
                LinearGradient(
                    colors: [t.bg, t.bgTint],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
    }
}

public struct LancerScreenHeader<Trailing: View>: View {
    private let kicker: String?
    private let title: String
    private let leadingAction: (() -> Void)?
    private let trailing: Trailing

    @Environment(\.lancerTokens) private var t

    public init(
        kicker: String? = nil,
        title: String,
        leadingAction: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.kicker = kicker
        self.title = title
        self.leadingAction = leadingAction
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if let leadingAction {
                DSCircleButton(
                    "line.3.horizontal",
                    accessibilityLabel: "Open navigation",
                    action: leadingAction
                )
            }

            VStack(alignment: .leading, spacing: 3) {
                if let kicker {
                    Text(kicker)
                        .font(.dsEditorialPt(17))
                        .foregroundStyle(t.accent)
                }
                Text(title)
                    .font(.dsDisplayPt(28, weight: .bold))
                    .foregroundStyle(t.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

public enum LancerAttentionTone {
    case attention
    case safe
    case working

    fileprivate var icon: String {
        switch self {
        case .attention: "exclamationmark.circle.fill"
        case .safe: "checkmark.shield.fill"
        case .working: "bolt.fill"
        }
    }
}

public struct LancerAttentionBand: View {
    private let eyebrow: String
    private let title: String
    private let detail: String
    private let tone: LancerAttentionTone
    private let action: (() -> Void)?

    @Environment(\.lancerTokens) private var t
    public init(
        eyebrow: String,
        title: String,
        detail: String,
        tone: LancerAttentionTone = .attention,
        action: (() -> Void)? = nil
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
        self.tone = tone
        self.action = action
    }

    public var body: some View {
        Group {
            if let action {
                Button {
                    Haptics.selection()
                    action()
                } label: { band }
                    .buttonStyle(.plain)
            } else {
                band
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var band: some View {
        HStack(spacing: 12) {
            Image(systemName: tone.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 34, height: 34)
                .background(foreground.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow.uppercased())
                    .font(.dsMonoPt(10, weight: .medium))
                    .tracking(1.1)
                    .foregroundStyle(foreground.opacity(0.82))
                Text(title)
                    .font(.dsDisplayPt(21, weight: .bold))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                Text(detail)
                    .font(.dsSansPt(12.5, weight: .medium))
                    .foregroundStyle(foreground.opacity(0.88))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(foreground.opacity(0.85))
            }
        }
        .padding(15)
        .background(background, in: RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(foreground.opacity(0.18), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .accessibilityHint(action == nil ? "" : "Opens the relevant control")
    }

    private var foreground: Color {
        switch tone {
        case .attention: return .white
        case .safe: return .white
        case .working: return t.text
        }
    }

    private var background: Color {
        switch tone {
        case .attention: return t.accent
        case .safe: return t.ok
        case .working: return t.warnSoft
        }
    }
}

/// The single grab handle for every bottom drawer/sheet. Place at the very top of a
/// drawer's content so all drawers read identically (and the dark workspace drawer
/// gets a visible handle the native `.presentationDragIndicator` can't reliably show).
public struct LancerGrabHandle: View {
    public enum Surface { case light, dark }
    private let surface: Surface

    @Environment(\.lancerTokens) private var t

    public init(on surface: Surface = .light) {
        self.surface = surface
    }

    public var body: some View {
        Capsule()
            .fill(surface == .dark ? Color.white.opacity(0.28) : t.text4.opacity(0.55))
            .frame(width: 38, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .accessibilityHidden(true)
    }
}

public struct LancerSectionLabel: View {
    private let title: String
    private let detail: String?

    @Environment(\.lancerTokens) private var t

    public init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.dsMonoPt(10, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(t.text4)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.dsMonoPt(10))
                    .foregroundStyle(t.text4)
            }
        }
    }
}

public extension View {
    func lancerSurfaceCard(padding: CGFloat = 14) -> some View {
        modifier(LancerSurfaceCardModifier(padding: padding))
    }
}

private struct LancerSurfaceCardModifier: ViewModifier {
    let padding: CGFloat
    @Environment(\.lancerTokens) private var t

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(t.surface, in: RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.045), radius: 8, y: 3)
    }
}
