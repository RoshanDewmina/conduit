#if os(iOS)
import SwiftUI

/// Header row: arbitrary leading content on the left, a row of `CursorIconButton`s
/// on the right. Kept concrete (AnyView + array of icon buttons) rather than
/// generic to stay simple and compile cleanly.
public struct CursorHeaderBar: View {
    private let leading: AnyView
    private let trailing: [CursorIconButton]

    public init(leading: AnyView, trailing: [CursorIconButton]) {
        self.leading = leading
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: CursorMetrics.headerSpacing) {
            leading
            Spacer()
            ForEach(Array(trailing.enumerated()), id: \.offset) { _, button in
                button
            }
        }
        .padding(.horizontal, CursorMetrics.headerHorizontalPadding)
        .padding(.top, CursorMetrics.headerTopPadding)
    }
}
#endif
