import SwiftUI

public extension View {
    func conduitGlassChrome(cornerRadius: CGFloat = 18, interactive: Bool = false) -> some View {
        modifier(ConduitGlassChrome(cornerRadius: cornerRadius, interactive: interactive))
    }

    func conduitGlassCircle(tint: Color? = nil, fallbackSurface: Color) -> some View {
        modifier(ConduitGlassCircle(tint: tint, fallbackSurface: fallbackSurface))
    }
}

private struct ConduitGlassChrome: ViewModifier {
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

private struct ConduitGlassCircle: ViewModifier {
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
