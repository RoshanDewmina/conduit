#if os(iOS)
import SwiftUI
import LancerCore

/// Small tappable capsule that shows / sets permission mode for one chat's
/// repo `cwd` (not the document-level Settings default).
///
/// Local `@AppStorage` is a cache only. Authoritative state is the daemon's
/// coarse mode for this cwd (`deny`/`ask`/`allow`), read/written via
/// `GovernanceHostActions` → SSH or relay `agentPermissionModeGet`/`Set`.
/// Never displays a mode the daemon has not confirmed (fail-closed).
struct ChatPermissionModePill: View {
    /// Conversation repo cwd — same value the dispatch / follow-up path uses.
    let cwd: String

    /// `false` (default): the original standalone capsule row above the
    /// composer. `true`: bare nested-menu content only (no capsule chrome, no
    /// inline error row) — meant to be embedded as a submenu inside another
    /// `Menu`'s content, e.g. the composer's `+` button (owner request
    /// 2026-07-18: "looks cleaner" folded into one menu than a separate row).
    /// Same state/daemon round-trip either way — only the outer chrome differs.
    var embedded: Bool = false

    @Environment(RelayFleetStore.self) private var relayFleetStore
    @AppStorage(AutonomySelection.storageKey) private var presetRaw: String =
        AutonomySelection.default.rawValue

    /// Daemon-confirmed preset. `nil` until the first successful GET/SET —
    /// the label stays on the local cache only as a provisional hint, and
    /// selection never commits to storage until the RPC succeeds.
    @State private var confirmedPreset: AutonomyPreset?
    @State private var isSyncing = false
    @State private var errorMessage: String?
    /// Set only by a user-initiated `apply()` failure, never by the
    /// background `refreshFromDaemon()` hydration — an alert firing from a
    /// routine cold-launch/reconnect fetch race (not a rare failure; this
    /// session hit that race repeatedly) would be a false-alarm interruption
    /// the moment the composer's `+` menu is built, before the user ever
    /// touched it. `errorMessage` still covers both paths for the
    /// non-embedded pill's quiet inline caption.
    @State private var applyErrorMessage: String?
    @State private var isShowingErrorAlert = false

    private var preset: AutonomyPreset {
        confirmedPreset ?? AutonomySelection.resolve(presetRaw)
    }

    @ViewBuilder private var optionsMenuContent: some View {
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
    }

    var body: some View {
        if embedded {
            Menu {
                optionsMenuContent
            } label: {
                if isSyncing {
                    Label("Permission: \(preset.shortLabel)", systemImage: "hourglass")
                } else {
                    Label("Permission: \(preset.shortLabel)", systemImage: "shield.lefthalf.filled")
                }
            }
            .disabled(isSyncing)
            .accessibilityIdentifier("permission-mode-pill")
            .accessibilityLabel(Text("Permission mode, \(preset.shortLabel)"))
            .accessibilityHint(Text("Choose how much the agent may do without asking"))
            .task { await refreshFromDaemon() }
            .onChange(of: applyErrorMessage) { _, newValue in
                isShowingErrorAlert = newValue != nil
            }
            .alert(
                "Couldn't change permission mode",
                isPresented: $isShowingErrorAlert,
                presenting: applyErrorMessage
            ) { _ in
                Button("OK") {}
            } message: { message in
                Text(message)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Menu {
                    optionsMenuContent
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
        applyErrorMessage = nil
        defer { isSyncing = false }
        do {
            try await GovernanceHostActions.setPermissionMode(
                option.coarsePermissionMode,
                cwd: cwd,
                relayFleetStore: relayFleetStore
            )
            confirmedPreset = option
            presetRaw = option.rawValue
        } catch {
            confirmedPreset = previous
            presetRaw = previous.rawValue
            errorMessage = error.localizedDescription
            applyErrorMessage = error.localizedDescription
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
                cwd: cwd,
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
