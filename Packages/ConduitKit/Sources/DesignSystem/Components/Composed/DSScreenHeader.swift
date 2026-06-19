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
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.dsDisplayPt(30, weight: .bold))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                trailing
            }
            if breadcrumb != nil || count != nil {
                HStack(spacing: 8) {
                    if let breadcrumb {
                        Text(breadcrumb).foregroundStyle(t.text2)
                    }
                    Spacer(minLength: 8)
                    if let count {
                        Text(count).foregroundStyle(t.text3)
                    }
                }
                .font(.dsSansPt(14))
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
    let onBack: (() -> Void)?
    let trailing: Trailing

    @Environment(\.conduitTokens) private var t

    public init(
        _ title: String,
        onBack: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.onBack = onBack
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(t.text)
                        .frame(width: 36, height: 36)
                        .background(t.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                                .strokeBorder(t.border, lineWidth: 1))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text(title)
                .font(.dsDisplayPt(24, weight: .bold))
                .foregroundStyle(t.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            trailing
        }
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
                .background(t.surface2)
                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1))
                // 36pt visual, 44pt touch target (Apple HIG minimum).
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? "")
    }
}
