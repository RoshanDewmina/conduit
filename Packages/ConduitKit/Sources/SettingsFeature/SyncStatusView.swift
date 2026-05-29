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
    @Environment(\.conduitTokens) private var t

    public init(engine: SyncEngine) {
        self.engine = engine
    }

    public var body: some View {
        VStack(spacing: 0) {
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

            if let error {
                t.border.frame(height: 0.5).padding(.horizontal, 16)
                Text(error)
                    .font(.dsSansPt(12))
                    .foregroundStyle(t.danger)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            t.border.frame(height: 0.5).padding(.horizontal, 16)

            Button {
                isSyncing = true
                Task {
                    try? await engine.syncNow()
                    lastSync = await engine.lastSyncDate
                    error = await engine.syncError
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
        }
        .task {
            lastSync = await engine.lastSyncDate
            error = await engine.syncError
        }
    }
}
#endif
