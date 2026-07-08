#if os(iOS)
import SwiftUI
import DesignSystem
import SSHTransport
import LancerCore
import SettingsFeature

/// Cursor-style Settings — the only user-facing settings surface. No bridge to
/// the legacy policy-bridge `SettingsView`.
public struct CursorSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.cursorScheme) private var cursorScheme
    @State private var purchaseManager = PurchaseManager.shared
    @State private var showingPairing = false
    @State private var activeDestination: SettingsDestination?
    @State private var showingResetConfirmation = false
    @State private var showingClearInvalidConfirmation = false

    private let relayMachineCount: Int
    private let invalidMachineCount: Int
    private let onPaired: ((E2ERelayClient, RelayMachineRecord) -> Void)?
    private let onClearInvalid: (() -> Void)?

    public init(
        relayMachineCount: Int = 0,
        invalidMachineCount: Int = 0,
        onPaired: ((E2ERelayClient, RelayMachineRecord) -> Void)? = nil,
        onClearInvalid: (() -> Void)? = nil
    ) {
        self.relayMachineCount = relayMachineCount
        self.invalidMachineCount = invalidMachineCount
        self.onPaired = onPaired
        self.onClearInvalid = onClearInvalid
    }

    private var colors: CursorColors { CursorColors.resolve(cursorScheme) }

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
                .foregroundColor(colors.primaryText)
                .padding(.leading, CursorMetrics.pageTitleLeadingPadding)
                .padding(.top, CursorMetrics.pageTitleTopPadding)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(spacing: 0) {
                    accountBanner

                    CursorSectionHeader("Account")
                    row(
                        title: "Account",
                        trailingText: "Signed in",
                        showChevron: true,
                        accessibilityIdentifier: "cursor.settings.row.account"
                    ) {
                        activeDestination = .account
                    }

                    CursorSectionHeader("Machines & Pairing")
                    row(
                        title: "Trusted machines",
                        trailingCount: relayMachineCount > 0 ? relayMachineCount : nil,
                        trailingText: pairingStatusText,
                        showChevron: true,
                        accessibilityIdentifier: "cursor.settings.row.trusted-machines"
                    ) {
                        showingPairing = true
                    }
                    if invalidMachineCount > 0 {
                        row(
                            title: "Clear dead pairings",
                            titleColor: colors.dangerRed,
                            trailingText: "\(invalidMachineCount) invalid",
                            showChevron: false,
                            accessibilityIdentifier: "cursor.settings.row.clear-dead-pairings"
                        ) {
                            showingClearInvalidConfirmation = true
                        }
                    }

                    CursorSectionHeader("Notifications")
                    row(
                        title: "Notifications",
                        trailingText: "Critical and high risk",
                        showChevron: true,
                        accessibilityIdentifier: "cursor.settings.row.notifications"
                    ) {
                        activeDestination = .notifications
                    }

                    CursorSectionHeader("Security & Approvals")
                    row(
                        title: "Policy defaults",
                        trailingText: "Always ask for risky actions",
                        showChevron: true,
                        accessibilityIdentifier: "cursor.settings.row.policy-defaults"
                    ) {
                        activeDestination = .policyDefaults
                    }
                    row(
                        title: "Audit log",
                        trailingText: "View, digest, export",
                        showChevron: true,
                        accessibilityIdentifier: "cursor.settings.row.audit-log"
                    ) {
                        activeDestination = .auditLog
                    }

                    CursorSectionHeader("Diagnostics")
                    row(
                        title: "Diagnostics & support",
                        trailingText: "Relay, daemon, push",
                        showChevron: true,
                        accessibilityIdentifier: "cursor.settings.row.diagnostics"
                    ) {
                        activeDestination = .diagnostics
                    }

                    CursorSectionHeader("Plan")
                    row(
                        title: "Plan",
                        trailingText: planStatusText,
                        showChevron: true,
                        accessibilityIdentifier: "cursor.settings.row.plan"
                    ) {
                        activeDestination = .plan
                    }

                    CursorSectionHeader("Support")
                    externalLinkRow(
                        title: "Suggest a Feature",
                        accessibilityIdentifier: "settings-suggest-feature",
                        url: Self.suggestFeatureURL
                    )
                    externalLinkRow(
                        title: "Report an Issue",
                        accessibilityIdentifier: "settings-report-issue",
                        url: Self.reportIssueURL
                    )

                    CursorSectionHeader("Legal & Reset")
                    row(
                        title: "Privacy policy",
                        trailingText: "Terms, licenses, security",
                        showChevron: true,
                        accessibilityIdentifier: "cursor.settings.row.privacy"
                    ) {
                        activeDestination = .privacy
                    }
                    row(
                        title: "Reset app data",
                        titleColor: colors.dangerRed,
                        showChevron: true,
                        accessibilityIdentifier: "cursor.settings.row.reset"
                    ) {
                        showingResetConfirmation = true
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(colors.background.ignoresSafeArea())
        .accessibilityIdentifier("cursor.settings")
        .sheet(isPresented: $showingPairing) {
            if let onPaired {
                CursorRelayPairingSheet(
                    existingMachineCount: relayMachineCount,
                    onPaired: onPaired
                )
            }
        }
        .sheet(item: $activeDestination) { destination in
            CursorSettingsStubSheet(destination: destination)
        }
        .alert("Reset app data?", isPresented: $showingResetConfirmation) {
            Button("Reset", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes local pairing, threads, and cached settings from this device. Your hosts and audit history on paired machines are not affected.")
        }
        .alert("Clear dead pairings?", isPresented: $showingClearInvalidConfirmation) {
            Button("Clear", role: .destructive) { onClearInvalid?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes \(invalidMachineCount) pairing\(invalidMachineCount == 1 ? "" : "s") that failed to restore. Re-pair from the machine to reconnect.")
        }
    }

    private var pairingStatusText: String? {
        relayMachineCount == 1 ? "1 machine paired" : nil
    }

    private var planStatusText: String {
        purchaseManager.hasCloudEntitlement ? "Lancer Cloud · active" : "Away Mode Solo"
    }

    private static let suggestFeatureURL = URL(
        string: "https://github.com/RoshanDewmina/conduit/issues/new?labels=enhancement&title=%5BFeature%5D%20"
    )!
    private static let reportIssueURL = URL(
        string: "https://github.com/RoshanDewmina/conduit/issues/new?labels=bug&title=%5BBug%5D%20"
    )!

    private var accountBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Local account")
                .font(CursorType.rowTitle)
                .foregroundColor(colors.primaryText)
            Text(accountBannerSubtitle)
                .font(CursorType.rowSecondary)
                .foregroundColor(colors.secondaryText)
        }
        .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(colors.hairline, lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(colors.cardBackground)
                )
        )
        .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .accessibilityIdentifier("cursor.settings.account-banner")
    }

    private var accountBannerSubtitle: String {
        if purchaseManager.hasCloudEntitlement {
            return "Local pairing · Lancer Cloud billing · Switch account"
        }
        return "Local pairing only · no hosted billing · Switch account"
    }

    @ViewBuilder
    private func row(
        title: String,
        titleColor: Color? = nil,
        trailingCount: Int? = nil,
        trailingText: String? = nil,
        showChevron: Bool,
        accessibilityIdentifier: String? = nil,
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
        .accessibilityIdentifier(accessibilityIdentifier ?? title)
    }

    @ViewBuilder
    private func externalLinkRow(
        title: String,
        accessibilityIdentifier: String,
        url: URL
    ) -> some View {
        let colors = CursorColors.resolve(cursorScheme)
        Button {
            openURL(url)
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: CursorMetrics.rowSpacing) {
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
                    .padding(.leading, CursorMetrics.rowHorizontalPadding)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

// MARK: - Stub destinations

private enum SettingsDestination: String, Identifiable {
    case account
    case notifications
    case policyDefaults
    case auditLog
    case diagnostics
    case plan
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: "Switch account"
        case .notifications: "Notifications"
        case .policyDefaults: "Policy defaults"
        case .auditLog: "Audit log"
        case .diagnostics: "Diagnostics & support"
        case .plan: "Plan"
        case .privacy: "Privacy & legal"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .account: "cursor.settings.account"
        case .notifications: "cursor.settings.notifications"
        case .policyDefaults: "cursor.settings.policy-defaults"
        case .auditLog: "cursor.settings.audit-log"
        case .diagnostics: "cursor.settings.diagnostics"
        case .plan: "cursor.settings.plan"
        case .privacy: "cursor.settings.privacy"
        }
    }

    var stubMessage: String {
        switch self {
        case .account:
            "Hot-swap between Lancer accounts and per-vendor CLI identities without re-pairing machines."
        case .notifications:
            "Configure push alerts for critical, high, and medium-risk approval actions."
        case .policyDefaults:
            "Set default autonomy and approval thresholds for new agents and hosts."
        case .auditLog:
            "View, digest, and export the hash-chained policy audit log from paired machines."
        case .diagnostics:
            "Relay connection health, daemon status, and push delivery diagnostics."
        case .plan:
            "Away Mode Solo runs on your own machines. Lancer Cloud adds hosted agents and managed AI via Stripe."
        case .privacy:
            "Terms of service, open-source licenses, and security architecture."
        }
    }
}

private struct CursorSettingsStubSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cursorScheme) private var cursorScheme
    @State private var purchaseManager = PurchaseManager.shared

    let destination: SettingsDestination

    private var colors: CursorColors { CursorColors.resolve(cursorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            CursorHeaderBar(
                leading: AnyView(
                    CursorIconButton(systemImageName: "xmark", action: { dismiss() })
                ),
                trailing: []
            )

            Text(destination.title)
                .font(CursorType.pageTitle)
                .foregroundColor(colors.primaryText)
                .padding(.leading, CursorMetrics.pageTitleLeadingPadding)
                .padding(.top, CursorMetrics.pageTitleTopPadding)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if destination == .plan {
                        planDetailCard
                    }

                    Text(destination.stubMessage)
                        .font(CursorType.rowSecondary)
                        .foregroundColor(colors.secondaryText)
                        .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
                        .padding(.top, 8)
                }
                .padding(.bottom, 24)
            }
        }
        .background(colors.background.ignoresSafeArea())
        .accessibilityIdentifier(destination.accessibilityIdentifier)
    }

    private var planDetailCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(purchaseManager.hasCloudEntitlement ? "Lancer Cloud" : "Away Mode Solo")
                .font(CursorType.rowTitle)
                .foregroundColor(colors.primaryText)
            Text(
                purchaseManager.hasCloudEntitlement
                    ? "Stripe cloud entitlement active — hosted agents and managed AI unlocked."
                    : "Local pairing on your own machines. Upgrade to Lancer Cloud for hosted agents."
            )
            .font(CursorType.rowSecondary)
            .foregroundColor(colors.secondaryText)
        }
        .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(colors.hairline, lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(colors.cardBackground)
                )
        )
        .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
        .padding(.top, 8)
    }
}
#endif
