#if os(iOS)
import SwiftUI

/// Destinations a settings row can route to. Callers receive this via
/// `onOpenRealSettings` so they can open the matching real settings section or
/// present a dedicated sheet without `CursorSettingsView` knowing the details.
public enum SettingsDestination: Sendable {
    case pairing
    case security
    case machines
    case audit
    case notifications
}

/// Visual clone of Lancer's approved Settings structure
/// (`docs/design-audit/workflows/06-settings.md`) rendered in the Cursor-style
/// visual language: same header bar, page title, and grouped `CursorListRow`
/// sections as `CursorHomeView` / `CursorWorkspacesView` — "boring on purpose,"
/// no policy hero or operations dashboard. In seeded mode rows are inert; in
/// live mode selected rows hand off to the real Settings destination.
public struct CursorSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingPairing = false

    private let relayMachineCount: Int
    private let onOpenRealSettings: ((SettingsDestination) -> Void)?

    public init(
        relayMachineCount: Int = 0,
        onOpenRealSettings: ((SettingsDestination) -> Void)? = nil
    ) {
        self.relayMachineCount = relayMachineCount
        self.onOpenRealSettings = onOpenRealSettings
    }

    public var body: some View {
        VStack(spacing: 0) {
            CursorHeaderBar(
                leading: AnyView(
                    CursorIconButton(systemImageName: "xmark", action: { dismiss() })
                ),
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
                        trailingText: "Signed in",
                        showChevron: true
                    )

                    CursorSectionHeader("Machines & Pairing")
                    pairMachineRow
                    row(
                        title: "Trusted machines",
                        trailingCount: relayMachineCount > 0 ? relayMachineCount : nil,
                        showChevron: true,
                        action: { onOpenRealSettings?(.machines) }
                    )

                    CursorSectionHeader("Notifications")
                    row(
                        title: "Notifications",
                        showChevron: true,
                        action: { onOpenRealSettings?(.notifications) }
                    )

                    CursorSectionHeader("Security & Approvals")
                    row(
                        title: "Security & Policy",
                        showChevron: true,
                        action: { onOpenRealSettings?(.security) }
                    )
                    row(
                        title: "Audit log",
                        showChevron: true,
                        action: { onOpenRealSettings?(.audit) }
                    )

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
        .accessibilityIdentifier("cursor.settings")
        .sheet(isPresented: $showingPairing) {
            CursorRelayPairingSheet(
                onSubmitCode: { _ in },
                onCancel: { showingPairing = false }
            )
            .presentationDetents([.large])
        }
    }

    // MARK: - Pair Machine row

    /// "Pair Machine" gets a subtitle line ("Required to dispatch") when no
    /// relay machines are paired yet, using a custom layout since `CursorListRow`
    /// does not support subtitles. When `onOpenRealSettings` is set the tap
    /// routes out to the caller; otherwise the pairing sheet is shown in-place
    /// (demo / seeded mode).
    private var pairMachineRow: some View {
        Button(action: openPairing) {
            VStack(spacing: 0) {
                HStack(spacing: CursorMetrics.rowSpacing) {
                    Text("Pair Machine")
                        .font(CursorType.rowTitle)
                        .foregroundColor(CursorColors.light.primaryText)
                    Spacer()
                    if relayMachineCount == 0 {
                        Text("Required to dispatch")
                            .font(CursorType.rowSecondary)
                            .foregroundColor(CursorColors.light.dangerRed)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(CursorColors.light.mutedText)
                }
                .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
                .padding(.vertical, CursorMetrics.rowVerticalPadding)
                Rectangle()
                    .fill(CursorColors.light.hairline)
                    .frame(height: CursorMetrics.rowHairlineHeight)
                    .padding(.leading, CursorMetrics.rowHorizontalPadding)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openPairing() {
        if let onOpenRealSettings {
            onOpenRealSettings(.pairing)
        } else {
            showingPairing = true
        }
    }

    // MARK: - Row helper

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
}
#endif
