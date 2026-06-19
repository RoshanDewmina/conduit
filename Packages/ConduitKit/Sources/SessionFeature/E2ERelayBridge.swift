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
    private var continueContinuation: CheckedContinuation<DispatchResult, Error>?

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
        // Send the raw DecisionData as the payload (NOT the E2ERelayMessage enum):
        // send() already wraps it as {type, payload}, and the daemon handler
        // unmarshals the typed params directly from payload. Passing the enum
        // double-nests it as {"approvalResponse":{…}}, which the daemon can't read —
        // mirror sendDispatch, which passes its raw DispatchParams struct.
        let decisionData = E2ERelayMessage.DecisionData(
            approvalID: approvalID, decision: decision, editedToolInput: editedToolInput
        )
        do {
            try await relayClient.send(type: "approvalResponse", payload: decisionData)
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

    /// Sends a run-control action (stop / pause / resume) for a dispatched relay
    /// run. Fire-and-forget: the daemon applies it via dispatcher.cancel/pause/resume
    /// and the resulting status streams back over agent.run.status. Returns false
    /// only if the relay isn't active.
    @discardableResult
    public func sendRunControl(runId: String, action: String) async -> Bool {
        guard isActive else { return false }
        struct ControlParams: Codable, Sendable { let runId: String; let action: String }
        do {
            try await relayClient.send(
                type: "agentRunControl",
                payload: ControlParams(runId: runId, action: action)
            )
            return true
        } catch {
            return false
        }
    }

    /// Sends a follow-up prompt to continue a relay run. The daemon re-launches the
    /// vendor CLI under a NEW runId (re-passing policy + budget) and replies with
    /// `runContinueResult`; output then streams under the new runId. Returns the
    /// result (with the new runId) so the caller can attach the continued turn.
    public func sendRunContinue(runId: String, prompt: String) async throws -> DispatchResult {
        guard isActive else { throw E2EError.notPaired }
        struct ContinueParams: Codable, Sendable { let runId: String; let prompt: String }
        try await relayClient.send(
            type: "agentRunContinue",
            payload: ContinueParams(runId: runId, prompt: prompt)
        )
        return try await withCheckedThrowingContinuation { c in
            self.continueContinuation = c
        }
    }

    // MARK: - Private

    private func handleRelayMessage(_ message: E2ERelayClient.ReceivedMessage) async {
        switch message.type {
        // message.payload is the FULL inner plaintext {type, payload:{…}} — every
        // case must unwrap RelayInnerEnvelope<T> to reach the typed params (same as
        // agentRunOutput/dispatchResult). Decoding the struct directly from the full
        // envelope silently fails (try? → nil), which is what dropped every relay
        // approval/status before this fix.
        case "approvalPending":
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<E2ERelayMessage.ApprovalData>.self, from: message.payload
            ) else { return }
            NotificationCenter.default.post(
                name: Notification.Name("conduitE2EApprovalReceived"),
                object: nil,
                userInfo: ["approvalData": env.payload]
            )

        case "agentStatus":
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<E2ERelayMessage.StatusData>.self, from: message.payload
            ) else { return }
            NotificationCenter.default.post(
                name: Notification.Name("conduitE2EStatusUpdate"),
                object: nil,
                userInfo: ["status": env.payload]
            )

        case "loopUpdate":
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<E2ERelayMessage.LoopData>.self, from: message.payload
            ) else { return }
            NotificationCenter.default.post(
                name: Notification.Name("conduitE2ELoopUpdate"),
                object: nil,
                userInfo: ["loopData": env.payload]
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

        case "runContinueResult":
            let envelope = try? JSONDecoder().decode(E2ERelayMessage.RelayInnerEnvelope<DispatchResult>.self, from: message.payload)
            if let result = envelope?.payload {
                continueContinuation?.resume(returning: result)
            } else {
                continueContinuation?.resume(throwing: E2EError.decryptFailed)
            }
            continueContinuation = nil

        case "agentRunOutput":
            // message.payload is the full inner plaintext {type, payload:{…}}, so
            // unwrap the envelope to the typed params — same pattern as dispatchResult.
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<RunOutputParams>.self, from: message.payload
            ) else { return }
            NotificationCenter.default.post(
                name: Notification.Name("conduitE2ERunOutput"),
                object: nil,
                userInfo: ["params": env.payload]
            )

        case "agentRunStatus":
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<RunStatusParams>.self, from: message.payload
            ) else { return }
            NotificationCenter.default.post(
                name: Notification.Name("conduitE2ERunStatus"),
                object: nil,
                userInfo: ["params": env.payload]
            )

        case "agentArtifact":
            guard let env = try? JSONDecoder().decode(
                E2ERelayMessage.RelayInnerEnvelope<AgentArtifactEvent>.self, from: message.payload
            ) else { return }
            NotificationCenter.default.post(
                name: Notification.Name("conduitE2EArtifact"),
                object: nil,
                userInfo: ["params": env.payload]
            )

        default:
            break
        }
    }
}
#endif
