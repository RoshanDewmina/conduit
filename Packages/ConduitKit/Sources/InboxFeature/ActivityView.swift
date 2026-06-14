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
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                DSStatusHeader(
                    connected: actions.isConnected,
                    policy: "balanced",
                    todaySpend: "$0.00"
                )

                // ── BLOCKS header (matches Inbox / Settings)
                DSScreenHeader(
                    "activity",
                    breadcrumb: "while you were away",
                    count: entries.isEmpty ? nil : "\(entries.count)"
                )

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if let loadError {
                            // Disconnected / load failure → a single DS empty state
                            // (matches Fleet's). Don't also render the feed's own
                            // "no decisions yet" empty state below it.
                            DSEmptyState(
                                icon: .server,
                                title: "not connected",
                                subtitle: loadError
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 24)
                        } else {
                            BridgeAuditFeedView(entries: entries)
                                .padding(.horizontal, 16)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }
                .refreshable { await load() }
            }

            if isLoading && entries.isEmpty { ProgressView() }
        }
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
