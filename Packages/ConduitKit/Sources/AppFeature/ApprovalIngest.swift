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
    private var task: Task<Void, Never>?

    public init(channel: DaemonChannel, repository: ApprovalRepository, hostName: String) {
        self.channel = channel
        self.repository = repository
        self.hostName = hostName
    }

    public func start() {
        task = Task { [channel, repository, hostName] in
            for await event in await channel.events {
                guard !Task.isCancelled else { break }
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
                        risk: params.approvalRisk
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
