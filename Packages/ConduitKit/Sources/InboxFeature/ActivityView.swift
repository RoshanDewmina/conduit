#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem
import PersistenceKit
import SettingsFeature
import SSHTransport

public struct ActivityView: View {
    private let actions: BridgeSessionActions
    private let auditRepository: AuditRepository?
    private let daemonChannel: DaemonChannel?
    @State private var entries: [AuditLogEntry] = []
    @State private var isLoading = false
    @State private var loadError: String?

    @Environment(\.conduitTokens) private var t

    public init(actions: BridgeSessionActions, auditRepository: AuditRepository? = nil, daemonChannel: DaemonChannel? = nil) {
        self.actions = actions
        self.auditRepository = auditRepository
        self.daemonChannel = daemonChannel
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
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

                            if let auditRepository {
                                auditSection(repository: auditRepository)
                            }
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

    @ViewBuilder
    private func auditSection(repository: AuditRepository) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FULL AUDIT LOG")
                .font(.dsMonoPt(11, weight: .medium))
                .tracking(11 * 0.10)
                .foregroundStyle(t.text3)
                .padding(.horizontal, 16)
                .padding(.top, 22)
                .padding(.bottom, 6)

            NavigationLink {
                AuditView(
                    viewModel: AuditViewModel(repository: repository),
                    daemonChannel: daemonChannel
                )
            } label: {
                HStack {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(t.accent)
                    Text("On-device audit log")
                        .font(.body)
                        .foregroundStyle(t.text1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(t.text4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
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
