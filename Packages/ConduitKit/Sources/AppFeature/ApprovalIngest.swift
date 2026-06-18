#if os(iOS)
import Foundation
import ConduitCore
import SSHTransport
import PersistenceKit
import NotificationsKit

public actor ApprovalIngest {
    private let channel: DaemonChannel
    private let repository: ApprovalRepository
    private let hostName: String
    private let runOutputStore: RunOutputStore?
    private var task: Task<Void, Never>?

    public init(channel: DaemonChannel, repository: ApprovalRepository, hostName: String, runOutputStore: RunOutputStore? = nil) {
        self.channel = channel
        self.repository = repository
        self.hostName = hostName
        self.runOutputStore = runOutputStore
    }

    public func start() {
        task = Task { [channel, repository, hostName, runOutputStore] in
            for await event in await channel.events {
                guard !Task.isCancelled else { break }
                if case .runOutput(let params) = event {
                    await runOutputStore?.appendOutput(params)
                    continue
                }
                if case .runStatus(let params) = event {
                    await runOutputStore?.updateStatus(params)
                    continue
                }
                if case .toolStart(let params) = event {
                    await runOutputStore?.appendToolStart(params)
                    continue
                }
                if case .approvalPending(let params) = event {
                    let sessionID = params.sessionId.flatMap { UUID(uuidString: $0) }.map(SessionID.init) ?? SessionID()
                    let approval = Approval(
                        id: ApprovalID(UUID(uuidString: params.id) ?? UUID()),
                        sessionID: sessionID,
                        agent: params.approvalAgent,
                        kind: params.approvalKind,
                        command: params.command,
                        patch: params.patch,
                        cwd: params.cwd,
                        risk: params.approvalRisk,
                        toolName: params.approvalToolName,
                        toolUseID: params.approvalToolUseID,
                        agentSessionID: params.approvalAgentSessionID,
                        toolInput: params.approvalToolInput,
                        blastRadius: params.blastRadius,
                        lastStateChangeAt: Date()
                    )
                    try? await repository.upsert(approval)
                    await Notifications.shared.notifyPendingApproval(approval, hostName: hostName)
                }
            }
        }
    }

    public func stop() {
        task?.cancel()
    }
}
#endif
