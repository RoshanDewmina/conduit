import SwiftUI

// MARK: - DSScreen — the standard feature-page scaffold
// One import to build a consistent page: native header (DSScreenHeader for a top-level
// screen, DSDetailHeader when `onBack` is provided) + a scrolling content slot with
// standard horizontal padding and spacing, over the app background. New feature screens
// should prefer this over hand-rolling `ScrollView { VStack { DSDetailHeader(...); ... } }`.

public struct DSScreen<Trailing: View, Content: View>: View {
    let title: String
    let subtitle: String?
    let onBack: (() -> Void)?
    let scrolls: Bool
    let contentSpacing: CGFloat
    let trailing: Trailing
    let content: Content

    @Environment(\.conduitTokens) private var t

    public init(
        _ title: String,
        subtitle: String? = nil,
        onBack: (() -> Void)? = nil,
        scrolls: Bool = true,
        contentSpacing: CGFloat = 16,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onBack = onBack
        self.scrolls = scrolls
        self.contentSpacing = contentSpacing
        self.trailing = trailing()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if scrolls {
                ScrollView { contentStack }
            } else {
                contentStack
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(t.bg.ignoresSafeArea())
    }

    @ViewBuilder private var header: some View {
        if let onBack {
            DSDetailHeader(title, onBack: onBack) { trailing }
        } else {
            DSScreenHeader(title, breadcrumb: subtitle) { trailing }
        }
    }

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 24)
    }
}
