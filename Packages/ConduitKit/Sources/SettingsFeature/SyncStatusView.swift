#if os(iOS)
import SwiftUI
import SyncKit
import DesignSystem

/// Embeddable iCloud sync card for SettingsView.
public struct SyncStatusView: View {
    let engine: SyncEngine
    @State private var lastSync: Date?
    @State private var error: String?
    @State private var isSyncing = false
    @State private var conflictCount = 0
    @State private var showScope = false
    @Environment(\.conduitTokens) private var t

    public init(engine: SyncEngine) {
        self.engine = engine
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 10) {
                Image(systemName: "icloud")
                    .font(.system(size: 15))
                    .foregroundStyle(t.accent)
                Text("iCloud Sync")
                    .font(.dsSansPt(15))
                    .foregroundStyle(t.text)
                Spacer()
                if isSyncing {
                    ProgressView().scaleEffect(0.8)
                } else if let lastSync {
                    Text(lastSync.formatted(date: .omitted, time: .shortened))
                        .font(.dsSansPt(13))
                        .foregroundStyle(t.text3)
                } else {
                    Text("Not synced")
                        .font(.dsSansPt(13))
                        .foregroundStyle(t.text3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Error banner
            if let error {
                t.border.frame(height: 0.5).padding(.horizontal, 16)
                Text(error)
                    .font(.dsSansPt(12))
                    .foregroundStyle(t.danger)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            // Conflict count
            if conflictCount > 0 {
                t.border.frame(height: 0.5).padding(.horizontal, 16)
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(t.warn)
                    Text("\(conflictCount) conflict\(conflictCount == 1 ? "" : "s") resolved (last-write-wins)")
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.warn)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            t.border.frame(height: 0.5).padding(.horizontal, 16)

            // Sync now button
            Button {
                isSyncing = true
                Task {
                    try? await engine.syncNow()
                    lastSync      = await engine.lastSyncDate
                    error         = await engine.syncError
                    conflictCount = await engine.conflictCount
                    isSyncing = false
                }
            } label: {
                Text("Sync now")
                    .font(.dsSansPt(14))
                    .foregroundStyle(isSyncing ? t.text3 : t.accent)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .disabled(isSyncing)

            // Scope disclosure
            t.border.frame(height: 0.5).padding(.horizontal, 16)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showScope.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("What syncs")
                        .font(.dsSansPt(13))
                        .foregroundStyle(t.text3)
                    Spacer()
                    Image(systemName: showScope ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(t.text3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if showScope {
                t.border.frame(height: 0.5).padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 6) {
                    syncRow(icon: "checkmark.circle", label: "Host metadata (name, address, tags, preferences)", color: t.ok)
                    syncRow(icon: "checkmark.circle", label: "Command snippets", color: t.ok)
                    syncRow(icon: "checkmark.circle", label: "SSH host fingerprints (TOFU)", color: t.ok)
                    syncRow(icon: "xmark.circle",     label: "SSH private keys (device-local only)", color: t.text3)
                    syncRow(icon: "info.circle",      label: "Key hint (fingerprint) syncs so you know which key to import on a new device", color: t.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .task {
            lastSync      = await engine.lastSyncDate
            error         = await engine.syncError
            conflictCount = await engine.conflictCount
            isSyncing     = await engine.isSyncing
        }
    }

    @ViewBuilder
    private func syncRow(icon: String, label: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
                .frame(width: 16)
            Text(label)
                .font(.dsSansPt(12))
                .foregroundStyle(t.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
