import SwiftUI

// MARK: - DSScreenHeader — the BLOCKS large-title header (Head1 pattern)
// Lowercase Chakra Petch title with a blinking blue `_` cursor, a `~/conduit › {sub} · {count}`
// breadcrumb, and the famicom spectrum rule. Used by Sessions / Inbox / Settings.

public struct DSScreenHeader<Trailing: View>: View {
    let title: String
    let breadcrumb: String?
    let count: String?
    let spectrumMode: SpectrumMode
    let trailing: Trailing

    @Environment(\.conduitTokens) private var t

    public init(
        _ title: String,
        breadcrumb: String? = nil,
        count: String? = nil,
        spectrumMode: SpectrumMode = .idle,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.breadcrumb = breadcrumb
        self.count = count
        self.spectrumMode = spectrumMode
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 0) {
                    Text(title.lowercased())
                        .font(.dsDisplayPt(30, weight: .bold))
                        .foregroundStyle(t.text)
                    Text("_")
                        .font(.dsDisplayPt(30, weight: .bold))
                        .foregroundStyle(t.accent)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                trailing
            }
            if breadcrumb != nil || count != nil {
                HStack(spacing: 8) {
                    if let breadcrumb {
                        Text("~/conduit").foregroundStyle(t.text4)
                        Text("›").foregroundStyle(t.accent)
                        Text(breadcrumb).foregroundStyle(t.text3)
                    }
                    Spacer(minLength: 8)
                    if let count {
                        Text(count).foregroundStyle(t.text2)
                    }
                }
                .font(.dsMonoPt(11))
                .lineLimit(1)
            }
            SpectrumBar(mode: spectrumMode, height: 3)
                .opacity(0.75)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

// MARK: - DSDetailHeader — BLOCKS header for pushed/sheet detail screens
// Square back button + lowercase Chakra Petch title with blue `_` cursor + spectrum rule.
// Replaces the system navigation bar (rounded Cancel/Save pills + SF title) on pushed screens.

public struct DSDetailHeader<Trailing: View>: View {
    let title: String
    let onBack: (() -> Void)?
    let spectrumMode: SpectrumMode
    let trailing: Trailing

    @Environment(\.conduitTokens) private var t

    public init(
        _ title: String,
        onBack: (() -> Void)? = nil,
        spectrumMode: SpectrumMode = .idle,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.onBack = onBack
        self.spectrumMode = spectrumMode
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let onBack {
                    Button {
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(t.text)
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
                }
                HStack(spacing: 0) {
                    Text(title.lowercased())
                        .font(.dsDisplayPt(24, weight: .bold))
                        .foregroundStyle(t.text)
                    Text("_")
                        .font(.dsDisplayPt(24, weight: .bold))
                        .foregroundStyle(t.accent)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                trailing
            }
            SpectrumBar(mode: spectrumMode, height: 3)
                .opacity(0.75)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

// MARK: - DSIconButton — square bordered action button (the BLOCKS `+` in the header)

public struct DSIconButton: View {
    let icon: DSIcon
    let action: () -> Void

    @Environment(\.conduitTokens) private var t

    public init(_ icon: DSIcon, action: @escaping () -> Void) {
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button {
            action()
        } label: {
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
    }
}
