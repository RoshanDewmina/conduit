#if os(iOS)
import SwiftUI
import DesignSystem

/// Visual clone of Cursor's own profile drawer (owner-supplied screenshots),
/// presented as a bottom sheet when the header avatar circle is tapped.
/// Usage and activity stats are explicitly deferred until Lancer has a real
/// local usage ledger; this drawer must not invent account or token data.
public struct CursorProfileDrawer: View {
    @Environment(\.cursorScheme) private var cursorScheme

    private let onClose: () -> Void
    private let onOpenSettings: () -> Void
    private let onSignOut: () -> Void

    public init(
        onClose: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onSignOut: @escaping () -> Void = {}
    ) {
        self.onClose = onClose
        self.onOpenSettings = onOpenSettings
        self.onSignOut = onSignOut
    }

    public var body: some View {
        CursorBottomSheetContainer(
            title: "Profile",
            leadingButton: (systemImageName: "xmark", action: onClose)
        ) {
            ScrollView {
                VStack(spacing: 0) {
                    identitySection
                    usageSection
                    streakSection

                    CursorSectionHeader("Plan")
                    row(iconSystemName: "arrow.up.circle", title: "Manage Plan", showChevron: true)

                    CursorSectionHeader("Support")
                    externalLinkRow(iconSystemName: "questionmark.circle", title: "Help")
                    externalLinkRow(iconSystemName: "envelope", title: "Contact Sales")
                    row(iconSystemName: "shippingbox", title: "Acknowledgements", showChevron: true)

                    CursorSectionHeader("More")
                    row(
                        iconSystemName: "rectangle.portrait.and.arrow.right",
                        title: "Sign out",
                        showChevron: false,
                        action: onSignOut
                    )

                    CursorSectionHeader("Lancer")
                    row(
                        iconSystemName: "gearshape",
                        title: "App Settings",
                        showChevron: true,
                        action: onOpenSettings
                    )

                    CursorSectionHeader("Danger Zone")
                    row(
                        iconSystemName: "trash",
                        title: "Delete Account",
                        titleColor: CursorColors.resolve(cursorScheme).dangerRed,
                        showChevron: false
                    )

                    footer
                }
                .padding(.bottom, CursorMetrics.sheetContentBottomPadding)
            }
        }
        .environment(\.cursorScheme, .light)
    }

    // MARK: Identity

    private var identitySection: some View {
        let colors = CursorColors.resolve(cursorScheme)
        return VStack(spacing: 6) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.29, green: 0.42, blue: 0.94),
                            Color(red: 0.62, green: 0.31, blue: 0.87)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
                .padding(.top, 8)
                .padding(.bottom, 12)

            Text("Local Lancer")
                .font(CursorType.cardTitle)
                .foregroundColor(colors.primaryText)

            Text("Self-hosted device")
                .font(CursorType.rowSecondary)
                .foregroundColor(colors.secondaryText)

            Text("Away Mode Solo")
                .font(CursorType.statusPill)
                .foregroundColor(colors.pillPrimaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Capsule().fill(colors.pillPrimaryBackground))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 20)
    }

    // MARK: Usage

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            CursorSectionHeader("Usage")

            deferredBlock(
                title: "Usage stats not built yet",
                body: "Lancer does not have a real token or run-usage ledger on this device yet."
            )
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
            .padding(.bottom, 20)
        }
    }

    // MARK: Streak

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CursorSectionHeader("Activity")

            deferredBlock(
                title: "Activity streak not built yet",
                body: "Conversation history is real; streak and calendar analytics are intentionally deferred."
            )
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
            .padding(.bottom, 8)
        }
    }

    private func deferredBlock(title: String, body: String) -> some View {
        let colors = CursorColors.resolve(cursorScheme)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(CursorType.rowTitle)
                .foregroundColor(colors.primaryText)
            Text(body)
                .font(CursorType.rowSecondary)
                .foregroundColor(colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(colors.cardBackground))
    }

    // MARK: Rows

    private func row(
        iconSystemName: String,
        title: String,
        titleColor: Color? = nil,
        showChevron: Bool,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button(action: action) {
            CursorListRow(
                iconSystemName: iconSystemName,
                title: title,
                titleColor: titleColor,
                showChevron: showChevron
            )
        }
        .buttonStyle(.plain)
    }

    /// Same visual language as `CursorListRow` but with a trailing
    /// external-link icon instead of a chevron, for rows that leave the app.
    private func externalLinkRow(iconSystemName: String, title: String) -> some View {
        let colors = CursorColors.resolve(cursorScheme)
        return Button(action: {}) {
            VStack(spacing: 0) {
                HStack(spacing: CursorMetrics.rowSpacing) {
                    Image(systemName: iconSystemName)
                        .font(.system(size: CursorMetrics.rowIconSize - 6, weight: .regular))
                        .foregroundColor(colors.secondaryText)
                        .frame(width: CursorMetrics.rowIconSize, height: CursorMetrics.rowIconSize)
                    Text(title)
                        .font(CursorType.rowTitle)
                        .foregroundColor(colors.primaryText)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colors.mutedText)
                }
                .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
                .padding(.vertical, CursorMetrics.rowVerticalPadding)
                Rectangle()
                    .fill(colors.hairline)
                    .frame(height: CursorMetrics.rowHairlineHeight)
                    .padding(.leading, CursorMetrics.rowHairlineLeadingInsetWithIcon)
            }
            // Same dead-tap-zone fix as CursorListRow/CursorThreadRow: without
            // this, a tap in the `Spacer()` gap between the title and the
            // trailing external-link glyph doesn't register as hitting the Button.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer

    private var footer: some View {
        let colors = CursorColors.resolve(cursorScheme)
        return Text("LANCER V1.0.0 (1)")
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundColor(colors.mutedText)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
    }
}
#endif
