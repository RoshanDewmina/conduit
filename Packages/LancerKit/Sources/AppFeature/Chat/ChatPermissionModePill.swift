#if os(iOS)
import SwiftUI
import LancerCore

/// Small tappable capsule that shows / sets permission mode.
///
/// Local `@AppStorage` is a cache only. Authoritative state is the daemon's
/// coarse policy default (`deny`/`ask`/`allow`), read/written via
/// `GovernanceHostActions` → SSH or relay `agentPermissionModeGet`/`Set`.
/// Never displays a mode the daemon has not confirmed (fail-closed).
struct ChatPermissionModePill: View {
    @Environment(RelayFleetStore.self) private var relayFleetStore
    @AppStorage(AutonomySelection.storageKey) private var presetRaw: String =
        AutonomySelection.default.rawValue

    /// Daemon-confirmed preset. `nil` until the first successful GET/SET —
    /// the label stays on the local cache only as a provisional hint, and
    /// selection never commits to storage until the RPC succeeds.
    @State private var confirmedPreset: AutonomyPreset?
    @State private var isSyncing = false
    @State private var errorMessage: String?

    private var preset: AutonomyPreset {
        confirmedPreset ?? AutonomySelection.resolve(presetRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                ForEach(AutonomyPreset.allCases, id: \.self) { option in
                    Button {
                        Task { await apply(option) }
                    } label: {
                        if option == preset {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                    .disabled(isSyncing)
                }
            } label: {
                HStack(spacing: 4) {
                    if isSyncing {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text(preset.shortLabel)
                        .font(.system(size: 15, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color(.secondarySystemFill).opacity(0.6)))
            }
            .buttonStyle(.plain)
            .disabled(isSyncing)
            .accessibilityIdentifier("permission-mode-pill")
            .accessibilityLabel(Text("Permission mode, \(preset.shortLabel)"))
            .accessibilityHint(Text("Choose how much the agent may do without asking"))

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("permission-mode-pill-error")
            }
        }
        .task { await refreshFromDaemon() }
    }

    /// Push the mapped coarse mode; only update the pill + AppStorage after
    /// the daemon confirms. On failure, leave the prior confirmed mode and
    /// surface the error — never show an unconfirmed selection.
    @MainActor
    private func apply(_ option: AutonomyPreset) async {
        guard !isSyncing else { return }
        let previous = confirmedPreset ?? AutonomySelection.resolve(presetRaw)
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }
        do {
            try await GovernanceHostActions.setPermissionMode(
                option.coarsePermissionMode,
                relayFleetStore: relayFleetStore
            )
            confirmedPreset = option
            presetRaw = option.rawValue
        } catch {
            confirmedPreset = previous
            presetRaw = previous.rawValue
            errorMessage = error.localizedDescription
            await refreshFromDaemon()
        }
    }

    /// Hydrate from the live host on thread open. Prefer the local cache label
    /// when it already maps to the daemon's coarse mode; otherwise adopt the
    /// closest preset. Fetch failure → error caption, no silent "success".
    @MainActor
    private func refreshFromDaemon() async {
        do {
            let mode = try await GovernanceHostActions.fetchPermissionMode(
                relayFleetStore: relayFleetStore
            )
            let preferred = AutonomySelection.resolve(presetRaw)
            let resolved = AutonomyPreset.reflecting(coarseMode: mode, preferred: preferred)
            confirmedPreset = resolved
            presetRaw = resolved.rawValue
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
