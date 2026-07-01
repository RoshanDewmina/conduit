#if os(iOS)
import SwiftUI
import LancerCore
import SSHTransport
import DesignSystem

/// Display-only row for a single paired relay machine. Deliberately dumb —
/// this feature module can't see `RelayFleetStore`/`RelayFleetStore.Machine`
/// (they live in `AppFeature`), so a later lane maps its own machine model
/// down into this shape before handing it here.
public struct RelayMachineRow: Identifiable, Sendable {
    public let id: RelayMachineID
    public let displayName: String
    public let isConnected: Bool

    public init(id: RelayMachineID, displayName: String, isConnected: Bool) {
        self.id = id
        self.displayName = displayName
        self.isConnected = isConnected
    }
}

/// Settings surface listing every paired relay machine, with an entry point
/// to pair another (up to `relayFleetMaxMachines`) and to unpair an existing
/// one. Pairing always routes through this list — even with zero machines —
/// so there's a single, consistent "Paired Machines" surface.
public struct RelayMachinesListView: View {
    let machines: [RelayMachineRow]
    let onPaired: (E2ERelayClient, RelayMachineRecord) -> Void
    let onUnpair: (RelayMachineID) -> Void

    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss

    public init(
        machines: [RelayMachineRow],
        onPaired: @escaping (E2ERelayClient, RelayMachineRecord) -> Void,
        onUnpair: @escaping (RelayMachineID) -> Void
    ) {
        self.machines = machines
        self.onPaired = onPaired
        self.onUnpair = onUnpair
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("paired machines", onBack: { dismiss() })

                    if machines.isEmpty == false {
                        sectionHead("MACHINES")
                        card {
                            ForEach(Array(machines.enumerated()), id: \.element.id) { index, machine in
                                if index > 0 { hairline }
                                machineRow(machine)
                            }
                        }
                    }

                    sectionHead(machines.isEmpty ? "GET STARTED" : "ADD ANOTHER")
                    card {
                        NavigationLink {
                            E2ERelayPairingView(existingMachineCount: machines.count, onPaired: onPaired)
                        } label: {
                            addMachineRow
                        }
                    }
                    .padding(.bottom, 36)
                }
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Rows

    private func machineRow(_ machine: RelayMachineRow) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(machine.isConnected ? t.risk(0) : t.text4)
                .frame(width: 8, height: 8)

            Text(machine.displayName)
                .font(.dsSansPt(15, weight: .medium))
                .foregroundStyle(t.text)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button(role: .destructive) {
                onUnpair(machine.id)
            } label: {
                Image(systemName: "trash")
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.danger)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Unpair \(machine.displayName)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var addMachineRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(t.accent)
            Text("Pair another machine")
                .font(.dsSansPt(15, weight: .medium))
                .foregroundStyle(t.text)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.dsSansPt(12, weight: .semibold))
                .foregroundStyle(t.text4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Layout helpers

    private func sectionHead(_ title: String) -> some View {
        Text(title)
            .font(.dsMonoPt(11, weight: .medium))
            .tracking(11 * 0.10)
            .foregroundStyle(t.text3)
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 6)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
            .padding(.horizontal, 18)
    }

    private var hairline: some View {
        DSDivider(.soft, leadingInset: 16)
    }
}

#endif
