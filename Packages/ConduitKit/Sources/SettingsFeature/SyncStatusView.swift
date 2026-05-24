#if os(iOS)
import SwiftUI
import SyncKit

public struct SyncStatusView: View {
    let engine: SyncEngine
    @State private var lastSync: Date?
    @State private var error: String?
    @State private var isSyncing = false

    public init(engine: SyncEngine) {
        self.engine = engine
    }

    public var body: some View {
        Section("iCloud Sync") {
            HStack {
                Label("Status", systemImage: "icloud")
                Spacer()
                if isSyncing {
                    ProgressView().scaleEffect(0.8)
                } else if let lastSync {
                    Text(lastSync.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not synced").foregroundStyle(.secondary)
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Button("Sync now") {
                isSyncing = true
                Task {
                    try? await engine.syncNow()
                    lastSync = await engine.lastSyncDate
                    error = await engine.syncError
                    isSyncing = false
                }
            }
            .disabled(isSyncing)
        }
        .task {
            lastSync = await engine.lastSyncDate
            error = await engine.syncError
        }
    }
}
#endif
