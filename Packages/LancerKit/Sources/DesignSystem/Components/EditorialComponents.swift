import SwiftUI

public enum LancerMotion {
    public static let navigation = Animation.smooth(duration: 0.36, extraBounce: 0)
    public static let emphasis = Animation.snappy(duration: 0.22, extraBounce: 0)

    public static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

public extension View {
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

/// Grab handle for bottom drawers (SSH diff drawer, etc.).
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
