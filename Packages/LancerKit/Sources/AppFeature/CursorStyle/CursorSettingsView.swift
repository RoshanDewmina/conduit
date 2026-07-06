#if os(iOS)
import SwiftUI

/// Visual clone of Lancer's approved Settings structure
/// (`docs/design-audit/workflows/06-settings.md`) rendered in the Cursor-style
/// visual language: same header bar, page title, and grouped `CursorListRow`
/// sections as `CursorHomeView` / `CursorWorkspacesView` — "boring on purpose,"
/// no policy hero or operations dashboard. In seeded mode rows are inert; in
/// live mode selected rows hand off to the real Settings destination.
public struct CursorSettingsView: View {
    private let onOpenRealSettings: (() -> Void)?

    public init(onOpenRealSettings: (() -> Void)? = nil) {
        self.onOpenRealSettings = onOpenRealSettings
    }

    public var body: some View {
        VStack(spacing: 0) {
            CursorHeaderBar(
                leading: AnyView(avatarCircle),
                trailing: []
            )

            Text("Settings")
                .font(CursorType.pageTitle)
                .foregroundColor(CursorColors.light.primaryText)
                .padding(.leading, CursorMetrics.pageTitleLeadingPadding)
                .padding(.top, CursorMetrics.pageTitleTopPadding)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(spacing: 0) {
                    CursorSectionHeader("Account")
                    row(
                        title: "Account",
                        trailingText: "Signed in as roshan@example.com",
                        showChevron: true
                    )

                    CursorSectionHeader("Machines & Pairing")
                    row(
                        title: "Trusted machines",
                        trailingCount: 3,
                        showChevron: true,
                        action: openRealSettings
                    )

                    CursorSectionHeader("Notifications")
                    row(title: "Notifications", showChevron: true)

                    CursorSectionHeader("Security & Approvals")
                    row(title: "Policy defaults", showChevron: true, action: openRealSettings)
                    row(title: "Audit log", showChevron: true, action: openRealSettings)

                    CursorSectionHeader("Diagnostics")
                    row(title: "Diagnostics & support", showChevron: true)

                    CursorSectionHeader("Plan")
                    row(
                        title: "Plan",
                        trailingText: "Away Mode Solo",
                        showChevron: true
                    )

                    CursorSectionHeader("Legal & Reset")
                    row(title: "Privacy policy", showChevron: true)
                    row(
                        title: "Reset app data",
                        titleColor: CursorColors.light.dangerRed,
                        showChevron: true
                    )
                }
                .padding(.bottom, 24)
            }
        }
        .background(CursorColors.light.background.ignoresSafeArea())
        .environment(\.cursorScheme, .light)
    }

    private func openRealSettings() {
        onOpenRealSettings?()
    }

    /// Wraps `CursorListRow` in a plain-style `Button` so every row has a real
    /// (if inert) tap target matching its chevron affordance — legitimate for
    /// this visual-only pass since there's nothing to navigate to yet.
    private func row(
        title: String,
        titleColor: Color? = nil,
        trailingCount: Int? = nil,
        trailingText: String? = nil,
        showChevron: Bool,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button(action: action) {
            CursorListRow(
                title: title,
                titleColor: titleColor,
                trailingCount: trailingCount,
                trailingText: trailingText,
                showChevron: showChevron
            )
        }
        .buttonStyle(.plain)
    }

    private var avatarCircle: some View {
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
            .frame(width: 44, height: 44)
    }
}
#endif
