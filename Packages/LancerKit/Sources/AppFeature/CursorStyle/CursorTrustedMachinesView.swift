#if os(iOS)
import SwiftUI
import DesignSystem
import LancerCore
import SSHTransport

/// Settings → Trusted machines — list, unpair, re-pair entry, and dead-pairing cleanup.
public struct CursorTrustedMachinesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cursorScheme) private var cursorScheme

    private let trustedMachines: [CursorTrustedMachineRow]
    private let invalidMachines: [CursorTrustedMachineRow]
    private let usesMockData: Bool
    private let onRequestPairing: (() -> Void)?
    private let onRemoveMachine: ((String) -> Void)?
    private let onClearInvalid: (() -> Void)?
    private let onPaired: ((E2ERelayClient, RelayMachineRecord) -> Void)?

    @State private var showingPairing = false
    @State private var machinePendingRemoval: CursorTrustedMachineRow?
    @State private var showingClearInvalidConfirmation = false

    public init(
        trustedMachines: [CursorTrustedMachineRow] = [],
        invalidMachines: [CursorTrustedMachineRow] = [],
        usesMockData: Bool = false,
        onRequestPairing: (() -> Void)? = nil,
        onRemoveMachine: ((String) -> Void)? = nil,
        onClearInvalid: (() -> Void)? = nil,
        onPaired: ((E2ERelayClient, RelayMachineRecord) -> Void)? = nil
    ) {
        self.trustedMachines = trustedMachines
        self.invalidMachines = invalidMachines
        self.usesMockData = usesMockData
        self.onRequestPairing = onRequestPairing
        self.onRemoveMachine = onRemoveMachine
        self.onClearInvalid = onClearInvalid
        self.onPaired = onPaired
    }

    private var colors: CursorColors { CursorColors.resolve(cursorScheme) }

    private var displayTrustedMachines: [CursorTrustedMachineRow] {
        if !trustedMachines.isEmpty { return trustedMachines }
        if usesMockData { return CursorTrustedMachineSnapshot.mockRows }
        return []
    }

    private var displayInvalidMachines: [CursorTrustedMachineRow] {
        invalidMachines
    }

    public var body: some View {
        VStack(spacing: 0) {
            CursorHeaderBar(
                leading: AnyView(
                    CursorIconButton(systemImageName: "xmark", action: { dismiss() })
                ),
                trailing: []
            )

            Text("Trusted machines")
                .font(CursorType.pageTitle)
                .foregroundColor(colors.primaryText)
                .padding(.leading, CursorMetrics.pageTitleLeadingPadding)
                .padding(.top, CursorMetrics.pageTitleTopPadding)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(spacing: 0) {
                    if displayTrustedMachines.isEmpty {
                        emptyState
                    } else {
                        CursorSectionHeader("Paired")
                        ForEach(displayTrustedMachines) { machine in
                            // Always offer Remove in live shell — buried ellipsis-only
                            // menus made the 3-machine cap feel like a dead end
                            // (2026-07-09 pairing unblock).
                            machineRow(machine, removable: onRemoveMachine != nil && !usesMockData)
                        }
                    }

                    if !displayInvalidMachines.isEmpty {
                        CursorSectionHeader("Dead pairings")
                        ForEach(displayInvalidMachines) { machine in
                            // Dead rows are removable one-by-one (same remove
                            // callback) so a full fleet of ghost sim pairings
                            // can be cleared without hunting for Clear-all.
                            machineRow(
                                machine,
                                removable: onRemoveMachine != nil && !usesMockData
                            )
                        }
                        if onClearInvalid != nil {
                            Button {
                                showingClearInvalidConfirmation = true
                            } label: {
                                CursorListRow(
                                    title: "Clear all dead pairings",
                                    titleColor: colors.dangerRed,
                                    trailingText: "\(displayInvalidMachines.count) invalid",
                                    showChevron: false
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("cursor.trusted-machines.clear-dead-pairings")
                        }
                    }

                    if onRequestPairing != nil || onPaired != nil {
                        pairCTASection
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(colors.background.ignoresSafeArea())
        .accessibilityIdentifier("cursor.trusted-machines")
        .sheet(isPresented: $showingPairing) {
            if let onPaired {
                CursorRelayPairingSheet(
                    // Cap must ignore dead pairings — same rule as RelayFleetStore.usableMachineCount.
                    existingMachineCount: displayTrustedMachines.filter { !$0.isInvalid }.count,
                    onPaired: onPaired
                )
            }
        }
        .alert(
            "Remove \(machinePendingRemoval?.displayName ?? "machine")?",
            isPresented: Binding(
                get: { machinePendingRemoval != nil },
                set: { if !$0 { machinePendingRemoval = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let id = machinePendingRemoval?.id {
                    onRemoveMachine?(id)
                }
                machinePendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                machinePendingRemoval = nil
            }
        } message: {
            if let machine = machinePendingRemoval {
                Text(
                    CursorTrustedMachineFormatting.removeConfirmationMessage(
                        displayName: machine.displayName,
                        pendingApprovalCount: machine.pendingApprovalCount
                    )
                )
            }
        }
        .alert("Clear dead pairings?", isPresented: $showingClearInvalidConfirmation) {
            Button("Clear", role: .destructive) { onClearInvalid?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            let count = displayInvalidMachines.count
            Text("Removes \(count) pairing\(count == 1 ? "" : "s") that failed to restore. Re-pair from the machine to reconnect.")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No machines paired")
                .font(CursorType.rowTitle)
                .foregroundColor(colors.primaryText)
            Text("Pair a machine to approve agent actions and steer runs from this phone.")
                .font(CursorType.rowSecondary)
                .foregroundColor(colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("cursor.trusted-machines.empty")
    }

    private var pairCTASection: some View {
        VStack(spacing: 12) {
            CursorPillButton(title: "Pair a machine", style: .primary, fullWidth: true) {
                requestPairing()
            }
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
            .padding(.top, 16)
            .accessibilityIdentifier("cursor.trusted-machines.pair-cta")
        }
    }

    private func requestPairing() {
        if onPaired != nil {
            showingPairing = true
        } else {
            onRequestPairing?()
            dismiss()
        }
    }

    @ViewBuilder
    private func machineRow(_ machine: CursorTrustedMachineRow, removable: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: CursorMetrics.rowSpacing) {
                statusDot(isConnected: machine.isConnected)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(machine.displayName)
                        .font(CursorType.rowTitle)
                        .foregroundColor(colors.primaryText)
                    Text(machine.shortMachineID)
                        .font(CursorType.rowSecondary)
                        .foregroundColor(colors.mutedText)
                    HStack(spacing: 8) {
                        Text(CursorTrustedMachineFormatting.connectionStatusLabel(isConnected: machine.isConnected))
                            .font(CursorType.rowSecondary)
                            .foregroundColor(machine.isConnected ? colors.successGreen : colors.secondaryText)
                        if let pairedLabel = CursorTrustedMachineFormatting.pairedSinceLabel(pairedAt: machine.pairedAt) {
                            Text("·")
                                .font(CursorType.rowSecondary)
                                .foregroundColor(colors.mutedText)
                            Text(pairedLabel)
                                .font(CursorType.rowSecondary)
                                .foregroundColor(colors.secondaryText)
                        }
                    }
                    if machine.pendingApprovalCount > 0 {
                        Text("\(machine.pendingApprovalCount) pending approval\(machine.pendingApprovalCount == 1 ? "" : "s")")
                            .font(CursorType.rowSecondary)
                            .foregroundColor(colors.orangeAccent)
                    }
                }
                Spacer(minLength: 8)

                if removable {
                    Button("Remove") {
                        machinePendingRemoval = machine
                    }
                    .font(CursorType.statusPill)
                    .foregroundColor(colors.dangerRed)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(colors.dangerRed.opacity(0.12), in: Capsule())
                    .accessibilityIdentifier("cursor.trusted-machines.remove.\(machine.shortMachineID)")
                }
            }
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
            .padding(.vertical, CursorMetrics.rowVerticalPadding)

            Rectangle()
                .fill(colors.hairline)
                .frame(height: CursorMetrics.rowHairlineHeight)
                .padding(.leading, CursorMetrics.rowHorizontalPadding)
        }
        .accessibilityIdentifier("cursor.trusted-machines.row.\(machine.shortMachineID)")
    }

    @ViewBuilder
    private func statusDot(isConnected: Bool) -> some View {
        Circle()
            .fill(isConnected ? colors.successGreen : colors.statusDotIdle)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}
#endif
