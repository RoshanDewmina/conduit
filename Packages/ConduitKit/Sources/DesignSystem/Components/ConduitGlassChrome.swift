import SwiftUI

public extension View {
    func conduitGlassChrome(cornerRadius: CGFloat = 18, interactive: Bool = false) -> some View {
        modifier(ConduitGlassChrome(cornerRadius: cornerRadius, interactive: interactive))
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
