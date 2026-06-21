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
    private let showsHeader: Bool
    @State private var entries: [AuditLogEntry] = []
    @State private var localEvents: [AuditEvent] = []
    @State private var isLoading = false
    @State private var localError: String?
    @State private var remoteStatus: String?

    @Environment(\.conduitTokens) private var t

    public init(
        actions: BridgeSessionActions,
        auditRepository: AuditRepository? = nil,
        daemonChannel: DaemonChannel? = nil,
        showsHeader: Bool = true
    ) {
        self.actions = actions
        self.auditRepository = auditRepository
        self.daemonChannel = daemonChannel
        self.showsHeader = showsHeader
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                if showsHeader {
                    DSScreenHeader(
                        "activity",
                        breadcrumb: "while you were away",
                        count: entries.isEmpty ? nil : "\(entries.count)"
                    )
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if let localError {
                            DSEmptyState(
                                icon: .alert,
                                title: "Couldn't load on-device activity",
                                subtitle: localError
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 24)
                        } else {
                            if localEvents.isEmpty && entries.isEmpty {
                                DSEmptyState(
                                    icon: .hourglass,
                                    title: "Nothing recorded yet",
                                    subtitle: remoteStatus ?? "Activity will appear here after Conduit connects to a machine."
                                )
                                .padding(.horizontal, 16)
                                .padding(.top, 24)
                            } else {
                                if !localEvents.isEmpty {
                                    localActivitySection
                                        .padding(.horizontal, 16)
                                }

                                if !entries.isEmpty {
                                    remoteActivitySection
                                        .padding(.horizontal, 16)
                                } else if let remoteStatus {
                                    remoteHistoryNotice(remoteStatus)
                                        .padding(.horizontal, 16)
                                }

                                if let auditRepository {
                                    auditSection(repository: auditRepository)
                                }
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

    private var localActivitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("ON THIS PHONE")
            ForEach(localEvents) { event in
                LocalAuditEventRow(event: event)
                if event.id != localEvents.last?.id {
                    Divider().background(t.divider)
                }
            }
        }
    }

    private var remoteActivitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("CONNECTED HOST")
            BridgeAuditFeedView(entries: entries)
        }
    }

    private func remoteHistoryNotice(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "server.rack")
                .foregroundStyle(t.text4)
            Text(message)
                .font(.dsSansPt(12.5))
                .foregroundStyle(t.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(t.surface2, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.dsMonoPt(11, weight: .medium))
            .tracking(1.1)
            .foregroundStyle(t.text3)
            .padding(.top, 8)
            .padding(.bottom, 6)
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
        isLoading = true
        defer { isLoading = false }
        if let auditRepository {
            do {
                localEvents = try await auditRepository.recent(limit: 100)
                localError = nil
            } catch {
                localError = "Your local audit database couldn't be read."
            }
        }

        guard actions.isConnected else {
            remoteStatus = "Connect a host to supplement this with the host's audit history."
            return
        }
        do {
            entries = try await actions.tailAudit(100)
            remoteStatus = entries.isEmpty ? "This connected host has not reported audit events yet." : nil
        } catch {
            remoteStatus = "The on-device activity is available, but host history couldn't be loaded right now."
        }
    }
}

private struct LocalAuditEventRow: View {
    let event: AuditEvent
    @Environment(\.conduitTokens) private var t

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(label)
                        .font(.dsSansPt(13, weight: .semibold))
                        .foregroundStyle(t.text)
                    Spacer()
                    Text(event.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.dsMonoPt(10))
                        .foregroundStyle(t.text4)
                }
                if !event.metadata.isEmpty {
                    Text(event.metadata.values.sorted().joined(separator: " · "))
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 10)
    }

    private var label: String {
        switch event.type {
        case .connect: "Machine connected"
        case .disconnect: "Machine disconnected"
        case .authFailure: "Authentication failed"
        case .hostKeyChanged: "Host key changed"
        case .approval: "Approval recorded"
        }
    }

    private var icon: String {
        switch event.type {
        case .connect: "checkmark.circle"
        case .disconnect: "minus.circle"
        case .authFailure: "exclamationmark.triangle"
        case .hostKeyChanged: "key.horizontal"
        case .approval: "hand.thumbsup"
        }
    }

    private var color: Color {
        switch event.type {
        case .connect, .approval: t.ok
        case .disconnect: t.text4
        case .authFailure, .hostKeyChanged: t.danger
        }
    }
}
#endif
