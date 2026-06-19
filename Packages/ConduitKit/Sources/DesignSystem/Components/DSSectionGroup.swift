import SwiftUI

public struct DSSectionGroup<Content: View>: View {
    private let title: String?
    private let content: Content

    @Environment(\.conduitTokens) private var t

    public init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.dsSansPt(13, weight: .semibold))
                    .foregroundStyle(t.text3)
                    .textCase(.uppercase)
            }
            VStack(spacing: 0) {
                content
            }
            .background(t.surface, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
        }
    }
}
