import SwiftUI

// MARK: - DSDivider — the canonical 1px hairline
// Replaces the repeated inline `Rectangle().fill(t.divider).frame(height: 1)` pattern.
// Use `.soft` for the inner line-soft hairline, `.strong` for the default line border.

public struct DSDivider: View {
    public enum Tone { case soft, line, strong }

    @Environment(\.lancerTokens) private var t

    private let tone: Tone
    private let color: Color?
    private let leadingInset: CGFloat
    private let trailingInset: CGFloat

    public init(_ tone: Tone = .soft,
                color: Color? = nil,
                leadingInset: CGFloat = 0,
                trailingInset: CGFloat = 0) {
        self.tone = tone
        self.color = color
        self.leadingInset = leadingInset
        self.trailingInset = trailingInset
    }

    private var resolved: Color {
        if let color { return color }
        switch tone {
        case .soft:   return t.divider
        case .line:   return t.border
        case .strong: return t.borderStrong
        }
    }

    public var body: some View {
        Rectangle()
            .fill(resolved)
            .frame(height: 1)
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .accessibilityHidden(true)
    }
}
