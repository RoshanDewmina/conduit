#if os(iOS)
import SwiftUI

/// Generic rounded-rectangle card container (leading-aligned content, padding,
/// `cardBackground`) for Work Thread's plan/to-do/proof cards and the PR
/// screen's "Resolve Conflicts to Merge" card. Callers compose whatever's
/// inside — this component only provides the container.
public struct CursorArtifactCard<Content: View>: View {
    @Environment(\.cursorScheme) private var cursorScheme

    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(CursorMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CursorMetrics.cardCornerRadius))
    }
}
#endif
