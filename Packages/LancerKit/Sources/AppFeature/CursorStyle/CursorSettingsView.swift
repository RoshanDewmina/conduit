#if os(iOS)
import SwiftUI
import SSHTransport
import LancerCore

/// Cursor-style Settings — the only user-facing settings surface. No bridge to
/// the legacy policy-bridge `SettingsView`.
public struct CursorSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingPairing = false

    private let relayMachineCount: Int
    private let onPaired: ((E2ERelayClient, RelayMachineRecord) -> Void)?

    public init(
        relayMachineCount: Int = 0,
        onPaired: ((E2ERelayClient, RelayMachineRecord) -> Void)? = nil
    ) {
        self.relayMachineCount = relayMachineCount
        self.onPaired = onPaired
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
                    row(
                        title: "Trusted machines",
                        trailingCount: relayMachineCount > 0 ? relayMachineCount : nil,
                        showChevron: true,
                        action: { showingPairing = true }
                    )

                    CursorSectionHeader("Notifications")
                    row(title: "Notifications", showChevron: true)

                    CursorSectionHeader("Security & Approvals")
                    row(title: "Policy defaults", showChevron: true)
                    row(title: "Audit log", showChevron: true)

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
            if let onPaired {
                CursorRelayPairingSheet(
                    existingMachineCount: relayMachineCount,
                    onPaired: onPaired
                )
            }
        }
    }

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
