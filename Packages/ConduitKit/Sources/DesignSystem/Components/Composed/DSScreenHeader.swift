import SwiftUI

// MARK: - DSScreenHeader — the standard product-page header
// System-style title, concise breadcrumb, and optional trailing control.

public struct DSScreenHeader<Trailing: View>: View {
    let title: String
    let breadcrumb: String?
    let count: String?
    let trailing: Trailing

    @Environment(\.conduitTokens) private var t

    public init(
        _ title: String,
        breadcrumb: String? = nil,
        count: String? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.breadcrumb = breadcrumb
        self.count = count
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let breadcrumb {
                Text(breadcrumb)
                    .font(.dsEditorialPt(17))
                    .foregroundStyle(t.accent)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.dsDisplayPt(30, weight: .bold))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                trailing
            }
            if let count {
                Text(count)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text4)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

// MARK: - DSDetailHeader — native-style detail chrome for pushed or sheet screens.

public struct DSDetailHeader<Trailing: View>: View {
    let title: String
    let breadcrumb: String?
    let onBack: (() -> Void)?
    let trailing: Trailing

    @Environment(\.conduitTokens) private var t

    public init(
        _ title: String,
        breadcrumb: String? = nil,
        onBack: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.breadcrumb = breadcrumb
        self.onBack = onBack
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let onBack {
                DSCircleButton(
                    "chevron.left",
                    accessibilityLabel: "Back",
                    action: onBack
                )
            }
            VStack(alignment: .leading, spacing: 3) {
                if let breadcrumb {
                    Text(breadcrumb)
                        .font(.dsEditorialPt(15))
                        .foregroundStyle(t.accent)
                        .lineLimit(1)
                }
                Text(title)
                    .font(.dsDisplayPt(24, weight: .bold))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            trailing
        }
        // Fixed row height pins the back button to the same vertical position on
        // every detail page, regardless of whether the page adds a trailing control.
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

// MARK: - DSIconButton — standard 44-point icon control.

public struct DSIconButton: View {
    let icon: DSIcon
    let accessibilityLabel: String?
    let action: () -> Void

    @Environment(\.conduitTokens) private var t

    public init(_ icon: DSIcon, accessibilityLabel: String? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            DSIconView(icon, size: 17, color: t.text)
                .frame(width: 36, height: 36)
                // 36pt visual, 44pt touch target (Apple HIG minimum).
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .conduitGlassCircle(fallbackSurface: t.surface)
        .accessibilityLabel(accessibilityLabel ?? "")
    }
}
