import SwiftUI

public struct DSReviewSheet<Content: View>: View {
    private let title: String
    private let dismissLabel: String
    private let content: Content

    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    public init(_ title: String, dismissLabel: String = "Close", @ViewBuilder content: () -> Content) {
        self.title = title
        self.dismissLabel = dismissLabel
        self.content = content()
    }

    public var body: some View {
        NavigationStack {
            reviewedContent
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(dismissLabel) { dismiss() }
                            .foregroundStyle(t.text)
                    }
                }
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    @ViewBuilder private var reviewedContent: some View {
        #if os(iOS)
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        #else
        content
            .navigationTitle(title)
        #endif
    }
}
