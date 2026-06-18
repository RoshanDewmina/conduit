#if os(iOS)
import Foundation
import ConduitCore
import SSHTransport
import PersistenceKit
import NotificationsKit

public actor ChatRunPersistenceSink {
    private let chatRepo: ChatConversationRepository
    private var outputBuffer: [String: String] = [:]

    public init(chatRepo: ChatConversationRepository) {
        self.chatRepo = chatRepo
    }

    public func handleRunOutput(_ params: RunOutputParams) {
        guard !params.runId.isEmpty else { return }
        outputBuffer[params.runId, default: ""] += params.chunk
    }

    public func handleRunStatus(_ params: RunStatusParams) {
        guard !params.runId.isEmpty else { return }
        let status: ConduitCore.ChatTurn.Status
        if params.status == "exited" {
            status = (params.exitCode == 0) ? .completed : .failed
        } else if params.status == "failed" {
            status = .failed
        } else {
            status = .running
        }
        let text = outputBuffer.removeValue(forKey: params.runId) ?? ""
        Task { try? await chatRepo.updateTurnOutput(runID: params.runId, assistantText: text, status: status) }
    }

    public func handleToolStart(_ params: ToolStartParams) {
        guard !params.runId.isEmpty else { return }
        Task {
            if let turn = try? await chatRepo.turnByRunID(params.runId) {
                let artifact = ChatArtifact(
                    conversationID: turn.conversationID, turnID: turn.id,
                    runID: params.runId, kind: .tool, title: params.toolName,
                    summary: nil, payloadJSON: params.inputJSON, status: .running
                )
                try? await chatRepo.upsertArtifact(artifact)
            }
        }
    }

    public func handleApprovalPending(_ params: ApprovalPendingParams) {
        guard let runID = params.runId, !runID.isEmpty else { return }
        Task { try? await chatRepo.associateApproval(approvalID: params.id, runID: runID) }
    }
}

public actor ApprovalIngest {
    private let channel: DaemonChannel
    private let repository: ApprovalRepository
    private let hostName: String
    private let runOutputStore: RunOutputStore?
    private let chatPersistenceSink: ChatRunPersistenceSink?
    private var task: Task<Void, Never>?

    public init(channel: DaemonChannel, repository: ApprovalRepository, hostName: String, runOutputStore: RunOutputStore? = nil, chatPersistenceSink: ChatRunPersistenceSink? = nil) {
        self.channel = channel
        self.repository = repository
        self.hostName = hostName
        self.runOutputStore = runOutputStore
        self.chatPersistenceSink = chatPersistenceSink
    }

    public func start() {
        task = Task { [channel, repository, hostName, runOutputStore, chatPersistenceSink] in
            for await event in await channel.events {
                guard !Task.isCancelled else { break }
                if case .runOutput(let params) = event {
                    await runOutputStore?.appendOutput(params)
                    await chatPersistenceSink?.handleRunOutput(params)
                    continue
                }
                if case .runStatus(let params) = event {
                    await runOutputStore?.updateStatus(params)
                    await chatPersistenceSink?.handleRunStatus(params)
                    continue
                }
                if case .toolStart(let params) = event {
                    await runOutputStore?.appendToolStart(params)
                    await chatPersistenceSink?.handleToolStart(params)
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
                    await chatPersistenceSink?.handleApprovalPending(params)
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
