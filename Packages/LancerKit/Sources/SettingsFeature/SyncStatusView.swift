#if os(iOS)
import SwiftUI
import SyncKit
import DesignSystem

/// Embeddable iCloud sync card for SettingsView. Reports combined status for
/// both `SyncEngine` (Hosts/Snippets, default zone) and `ConversationSyncEngine`
/// (conversation mirror, Task 8, `LancerConversations` zone) — two engines,
/// one card, since from the user's point of view it's all "iCloud Sync".
public struct SyncStatusView: View {
    let engine: SyncEngine
    let conversationEngine: ConversationSyncEngine?
    @State private var lastSync: Date?
    @State private var error: String?
    @State private var isSyncing = false
    @State private var conflictCount = 0
    @State private var conversationLastSync: Date?
    @State private var conversationError: String?
    @State private var conversationIsSyncing = false
    @State private var showScope = false
    @Environment(\.lancerTokens) private var t

    public init(engine: SyncEngine, conversationEngine: ConversationSyncEngine? = nil) {
        self.engine = engine
        self.conversationEngine = conversationEngine
    }

    private var combinedIsSyncing: Bool { isSyncing || conversationIsSyncing }
    private var combinedLastSync: Date? {
        switch (lastSync, conversationLastSync) {
        case let (a?, b?): return max(a, b)
        case let (a?, nil): return a
        case let (nil, b?): return b
        case (nil, nil): return nil
        }
    }
    private var combinedError: String? { error ?? conversationError }

    private var syncHeaderAccessibilityLabel: String {
        if combinedIsSyncing { return "iCloud Sync, syncing" }
        if let combinedLastSync {
            return "iCloud Sync, last synced \(combinedLastSync.formatted(date: .omitted, time: .shortened))"
        }
        return "iCloud Sync, not synced"
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 10) {
                Image(systemName: "icloud")
                    .font(.dsSansPt(15))
                    .foregroundStyle(t.accent)
                Text("iCloud Sync")
                    .font(.dsSansPt(15))
                    .foregroundStyle(t.text)
                Spacer()
                if combinedIsSyncing {
                    ProgressView().scaleEffect(0.8)
                } else if let combinedLastSync {
                    Text(combinedLastSync.formatted(date: .omitted, time: .shortened))
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel(syncHeaderAccessibilityLabel)

            // Error banner
            if let combinedError {
                t.border.frame(height: 0.5).padding(.horizontal, 16)
                Text(combinedError)
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
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.warn)
                        .accessibilityHidden(true)
                    Text("\(conflictCount) conflict\(conflictCount == 1 ? "" : "s") resolved (last-write-wins)")
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.warn)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(conflictCount) sync conflict\(conflictCount == 1 ? "" : "s") resolved, last write wins")
            }

            t.border.frame(height: 0.5).padding(.horizontal, 16)

            // Sync now button
            Button {
                isSyncing = true
                conversationIsSyncing = conversationEngine != nil
                Task {
                    try? await engine.syncNow()
                    lastSync      = await engine.lastSyncDate
                    error         = await engine.syncError
                    conflictCount = await engine.conflictCount
                    isSyncing = false
                }
                if let conversationEngine {
                    Task {
                        try? await conversationEngine.syncNow()
                        conversationLastSync = await conversationEngine.lastSyncDate
                        conversationError    = await conversationEngine.syncError
                        conversationIsSyncing = false
                    }
                }
            } label: {
                Text("Sync now")
                    .font(.dsSansPt(14))
                    .foregroundStyle(combinedIsSyncing ? t.text3 : t.accent)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .disabled(combinedIsSyncing)
            .accessibilityLabel("Sync now")

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
                        .font(.dsSansPt(11, weight: .medium))
                        .foregroundStyle(t.text3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showScope ? "Hide what syncs" : "Show what syncs")
            .accessibilityValue(showScope ? "expanded" : "collapsed")

            if showScope {
                t.border.frame(height: 0.5).padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 6) {
                    syncRow(icon: "checkmark.circle", label: "Host metadata (name, address, tags, preferences)", color: t.ok)
                    syncRow(icon: "checkmark.circle", label: "Command snippets", color: t.ok)
                    syncRow(icon: "checkmark.circle", label: "SSH host fingerprints (TOFU)", color: t.ok)
                    syncRow(icon: "xmark.circle",     label: "SSH private keys (device-local only)", color: t.text3)
                    syncRow(icon: "info.circle",      label: "Key hint (fingerprint) syncs so you know which key to import on a new device", color: t.accent)
                    if conversationEngine != nil {
                        syncRow(icon: "checkmark.circle", label: "Conversation history (title, transcript, status) across your Apple devices", color: t.ok)
                        syncRow(icon: "info.circle",      label: "The host you're connected to always has the current, authoritative copy — iCloud only restores history to a new device", color: t.accent)
                    }
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
            if let conversationEngine {
                conversationLastSync  = await conversationEngine.lastSyncDate
                conversationError     = await conversationEngine.syncError
                conversationIsSyncing = await conversationEngine.isSyncing
            }
        }
    }

    @ViewBuilder
    private func syncRow(icon: String, label: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.dsSansPt(12))
                .foregroundStyle(color)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(label)
                .font(.dsSansPt(12))
                .foregroundStyle(t.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}
#endif
