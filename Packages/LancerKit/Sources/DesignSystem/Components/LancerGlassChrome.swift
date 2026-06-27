import SwiftUI

public extension View {
    func lancerGlassChrome(cornerRadius: CGFloat = 18, interactive: Bool = false) -> some View {
        modifier(LancerGlassChrome(cornerRadius: cornerRadius, interactive: interactive))
    }

    func lancerGlassCircle(tint: Color? = nil, fallbackSurface: Color) -> some View {
        modifier(LancerGlassCircle(tint: tint, fallbackSurface: fallbackSurface))
    }
}

private struct LancerGlassChrome: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(iOS)
        if interactive {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        }
#else
        content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
#endif
    }
}

private struct LancerGlassCircle: ViewModifier {
    let tint: Color?
    let fallbackSurface: Color

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(iOS)
        if let tint {
            content
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(tint).interactive(), in: Circle())
        } else {
            content
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
        }
#else
        content
            .buttonStyle(.plain)
            .background(tint ?? fallbackSurface, in: Circle())
#endif
    }
}
