#if os(iOS)
import Foundation
import LancerCore
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
        let status: LancerCore.ChatTurn.Status
        if params.status == "exited" {
            status = (params.exitCode == 0) ? .completed : .failed
        } else if params.status == "failed" {
            status = .failed
        } else {
            status = .running
        }
        let text = outputBuffer.removeValue(forKey: params.runId) ?? ""
        Task {
            try? await chatRepo.updateTurnOutput(runID: params.runId, assistantText: text, status: status)
            if status == .completed || status == .failed {
                try? await chatRepo.updateArtifactStatuses(
                    runID: params.runId,
                    status: status == .completed ? .done : .failed
                )
            }
        }
    }

    public func handleToolStart(_ params: ToolStartParams) {
        handleArtifact(AgentArtifactEvent(
            artifactID: params.toolId,
            runID: params.runId,
            kind: "tool",
            title: params.toolName,
            payloadJSON: params.inputJSON
        ))
    }

    public func handleArtifact(_ event: AgentArtifactEvent) {
        guard !event.runID.isEmpty, !event.artifactID.isEmpty else { return }
        Task {
            if let turn = try? await chatRepo.turnByRunID(event.runID) {
                let artifact = ChatArtifact(
                    id: event.artifactID,
                    conversationID: turn.conversationID,
                    turnID: turn.id,
                    runID: event.runID,
                    kind: ChatArtifact.Kind(rawValue: event.kind) ?? .tool,
                    title: event.title,
                    summary: event.summary,
                    payloadJSON: Self.persistablePayload(event.payloadJSON),
                    status: ChatArtifact.Status(rawValue: event.status) ?? .running
                )
                try? await chatRepo.upsertArtifact(artifact)
                // Same notify LiveThreadView listens for (receipt/question paths).
                await Self.postThreadArtifactUpdate(conversationID: turn.conversationID)
            }
        }
    }

    private static func persistablePayload(_ payload: String) -> String {
        let limit = 64 * 1024
        guard payload.utf8.count > limit else { return payload }
        return String(payload.prefix(limit)) + "\\n[artifact payload truncated]"
    }

    public func handleApprovalPending(_ params: ApprovalPendingParams) {
        guard let runID = params.runId, !runID.isEmpty else { return }
        Task { try? await chatRepo.associateApproval(approvalID: params.id, runID: runID) }
    }

    /// Store an incoming `QuestionPendingParams` as a `.question` artifact so it
    /// appears in the work-thread's artifact list. The payloadJSON encodes a
    /// `QuestionArtifactPayload` with no answer yet; `QuestionCardModel.mergeAnswer`
    /// updates it once the user submits a response.
    public func handleQuestionPending(_ params: QuestionPendingParams) {
        guard let runID = params.runId, !runID.isEmpty else { return }
        Task {
            guard let payloadData = try? JSONEncoder().encode(QuestionArtifactPayload(event: params)),
                  let payloadJSON = String(data: payloadData, encoding: .utf8) else { return }
            if let turn = try? await chatRepo.turnByRunID(runID) {
                let artifact = ChatArtifact(
                    id: "question:\(params.id)",
                    conversationID: turn.conversationID,
                    turnID: turn.id,
                    runID: runID,
                    kind: .question,
                    title: "Question",
                    payloadJSON: payloadJSON,
                    status: .running
                )
                try? await chatRepo.upsertArtifact(artifact)
                await Self.postThreadArtifactUpdate(conversationID: turn.conversationID)
            }
        }
    }

    public func handleRunReceipt(_ receipt: ProofReceipt) {
        guard !receipt.runId.isEmpty else { return }
        guard let payloadData = try? JSONEncoder().encode(receipt),
              let payloadJSON = String(data: payloadData, encoding: .utf8) else { return }
        Task {
            if let conversationID = try? await chatRepo.upsertReceipt(
                runID: receipt.runId,
                payloadJSON: Self.persistablePayload(payloadJSON)
            ) {
                await Self.postThreadArtifactUpdate(conversationID: conversationID)
            }
        }
    }

    private static func postThreadArtifactUpdate(conversationID: String) async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: Notification.Name("lancerChatArtifactPersisted"),
                object: nil,
                userInfo: ["conversationID": conversationID]
            )
        }
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
                if case .artifact(let params) = event {
                    await chatPersistenceSink?.handleArtifact(params)
                    continue
                }
                if case .runReceipt(let receipt) = event {
                    await chatPersistenceSink?.handleRunReceipt(receipt)
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
                        lastStateChangeAt: Date(),
                        contentHash: params.approvalContentHash
                    )
                    try? await repository.upsert(approval)
                    await chatPersistenceSink?.handleApprovalPending(params)
                    await Notifications.shared.notifyPendingApproval(approval, hostName: hostName)
                }
                if case .questionPending(let params) = event {
                    await chatPersistenceSink?.handleQuestionPending(params)
                }
            }
        }
    }

    public func stop() {
        task?.cancel()
    }
}
#endif
