#if os(iOS)
import SwiftUI

/// Production sheet wrapper using Cursor chrome (replaces `LancerDrawer`).
public struct CursorDrawer<Content: View>: View {
    @Environment(\.cursorScheme) private var cursorScheme
    @Environment(\.dismiss) private var dismiss

    private let title: String?
    private let subtitle: String?
    private let detents: Set<PresentationDetent>
    private let content: Content

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        detents: Set<PresentationDetent> = [.medium, .large],
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.detents = detents
        self.content = content()
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        VStack(spacing: 0) {
            Capsule()
                .fill(colors.mutedText)
                .frame(width: CursorMetrics.sheetDragHandleWidth, height: CursorMetrics.sheetDragHandleHeight)
                .padding(.top, CursorMetrics.sheetDragHandleTopPadding)
                .padding(.bottom, CursorMetrics.sheetDragHandleBottomPadding)

            if let title {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(CursorType.sheetTitle)
                            .foregroundColor(colors.primaryText)
                        if let subtitle {
                            Text(subtitle)
                                .font(CursorType.rowSecondary)
                                .foregroundColor(colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    CursorIconButton(systemImageName: "xmark", action: dismiss.callAsFunction)
                }
                .padding(.horizontal, CursorMetrics.sheetHeaderHorizontalPadding)
                .padding(.bottom, 12)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(colors.sheetBackground)
        .presentationDetents(detents)
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(CursorMetrics.sheetTopCornerRadius)
        .presentationBackground(colors.sheetBackground)
    }
}
#endif
