import SwiftUI

// MARK: - dsCard — the canonical BLOCKS surface card chrome
// surface fill + 1pt border + r4 continuous corners. Matches the inbox/activity
// card language so list-style screens (Fleet, Activity) read as the same system.

private struct DSCardModifier: ViewModifier {
    let padding: CGFloat
    @Environment(\.lancerTokens) private var t

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1))
    }
}

public extension View {
    /// Wrap a view in the standard surface card (fill + border + rounded corners).
    func dsCard(padding: CGFloat = 14) -> some View {
        modifier(DSCardModifier(padding: padding))
    }
}
