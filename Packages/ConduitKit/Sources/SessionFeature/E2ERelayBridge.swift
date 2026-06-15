#if os(iOS)
import Foundation
import ConduitCore
import SSHTransport

/// Bridges E2E relay messages to the approval flow and dispatch.
/// When the relay is paired, approvals and dispatch go through E2E instead of SSH.
@MainActor
public final class E2ERelayBridge: ObservableObject {

    @Published public private(set) var isActive: Bool = false
    private let relayClient: E2ERelayClient
    private let approvalRelay: ApprovalRelay
    private var messageTask: Task<Void, Never>?
    private var dispatchContinuation: CheckedContinuation<DispatchResult, Error>?

    public init(relayClient: E2ERelayClient, approvalRelay: ApprovalRelay) {
        self.relayClient = relayClient
        self.approvalRelay = approvalRelay
    }

    /// Start bridging E2E relay messages to the approval flow
    public func start() {
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            guard let self else { return }
            for await message in self.relayClient.messages {
                await self.handleRelayMessage(message)
            }
        }

        Task { [weak self] in
            guard let self else { return }
            for await state in self.relayClient.$pairingState.values {
                self.isActive = (state == .paired)
            }
        }
    }

    public func stop() {
        messageTask?.cancel()
        messageTask = nil
        isActive = false
    }

    /// Send an approval decision through the E2E relay.
    /// Returns true if the message was sent, false if the relay is not active.
    @discardableResult
    public func sendDecision(approvalID: String, decision: String, editedToolInput: String?) async -> Bool {
        guard isActive else { return false }
        let decisionMsg = E2ERelayMessage.approvalResponse(
            .init(approvalID: approvalID, decision: decision, editedToolInput: editedToolInput)
        )
        do {
            try await relayClient.send(type: "approvalResponse", payload: decisionMsg)
            return true
        } catch {
            return false
        }
    }

    /// Dispatch an agent run through the E2E relay.
    /// Returns the dispatch result, or nil if the relay is not active.
    public func sendDispatch(agent: String, cwd: String, prompt: String, budgetUSD: Double?, model: String?) async throws -> DispatchResult {
        guard isActive else {
            throw E2EError.notPaired
        }
        let params = E2ERelayMessage.DispatchParams(
            agent: agent, cwd: cwd, prompt: prompt,
            model: model, budgetUSD: budgetUSD ?? 0
        )
        try await relayClient.send(type: "agentDispatch", payload: params)
        return try await withCheckedThrowingContinuation { c in
            self.dispatchContinuation = c
        }
    }

    /// Sends a follow-up prompt to an already-running relay dispatch so the agent
    /// continues the same run. Output streams back via the existing
    /// `agent.run.output` path into the same runId. Fire-and-forget.
    public func sendRunContinue(runId: String, prompt: String) async throws {
        guard isActive else { return }
        struct ContinueParams: Codable, Sendable { let runId: String; let prompt: String }
        try await relayClient.send(
            type: "agentRunContinue",
            payload: ContinueParams(runId: runId, prompt: prompt)
        )
    }

    // MARK: - Private

    private func handleRelayMessage(_ message: E2ERelayClient.ReceivedMessage) async {
        switch message.type {
        case "approvalPending":
            guard let approval = try? JSONDecoder().decode(E2ERelayMessage.ApprovalData.self, from: message.payload)
            else { return }
            NotificationCenter.default.post(
                name: Notification.Name("conduitE2EApprovalReceived"),
                object: nil,
                userInfo: ["approvalData": approval]
            )

        case "agentStatus":
            guard let status = try? JSONDecoder().decode(E2ERelayMessage.StatusData.self, from: message.payload)
            else { return }
            NotificationCenter.default.post(
                name: Notification.Name("conduitE2EStatusUpdate"),
                object: nil,
                userInfo: ["status": status]
            )

        case "loopUpdate":
            guard let loopData = try? JSONDecoder().decode(E2ERelayMessage.LoopData.self, from: message.payload)
            else { return }
            NotificationCenter.default.post(
                name: Notification.Name("conduitE2ELoopUpdate"),
                object: nil,
                userInfo: ["loopData": loopData]
            )

        case "dispatchResult":
            let envelope = try? JSONDecoder().decode(E2ERelayMessage.RelayInnerEnvelope<DispatchResult>.self, from: message.payload)
            if let result = envelope?.payload {
                dispatchContinuation?.resume(returning: result)
                dispatchContinuation = nil
            } else {
                dispatchContinuation?.resume(throwing: E2EError.decryptFailed)
                dispatchContinuation = nil
            }

        case "agentRunOutput":
            NotificationCenter.default.post(
                name: Notification.Name("conduitE2ERunOutput"),
                object: nil,
                userInfo: ["payload": message.payload]
            )

        case "agentRunStatus":
            NotificationCenter.default.post(
                name: Notification.Name("conduitE2ERunStatus"),
                object: nil,
                userInfo: ["payload": message.payload]
            )

        default:
            break
        }
    }
}
#endif
