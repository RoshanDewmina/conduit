#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem

public struct ActivityView: View {
    private let actions: BridgeSessionActions
    @State private var entries: [AuditLogEntry] = []
    @State private var isLoading = false
    @State private var loadError: String?

    @Environment(\.conduitTokens) private var t

    public init(actions: BridgeSessionActions) {
        self.actions = actions
    }

    public var body: some View {
        List {
            if let loadError {
                Section { Text(loadError).font(.caption).foregroundStyle(t.text3) }
            }
            Section {
                BridgeAuditFeedView(entries: entries)
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .overlay { if isLoading && entries.isEmpty { ProgressView() } }
        .task { await load() }
    }

    private func load() async {
        guard actions.isConnected else {
            loadError = "Connect to a host to see what your agents did while you were away."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await actions.tailAudit(100)
            loadError = nil
        } catch {
            loadError = "Couldn't load activity from the bridge."
        }
    }
}
#endif
