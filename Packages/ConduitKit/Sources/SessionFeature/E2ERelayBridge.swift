#if os(iOS)
import Foundation
import ConduitCore
import SSHTransport

/// Bridges E2E relay messages to the approval flow.
/// When the relay is paired, approvals come through E2E instead of SSH.
@MainActor
public final class E2ERelayBridge: ObservableObject {

    @Published public private(set) var isActive: Bool = false
    private let relayClient: E2ERelayClient
    private let approvalRelay: ApprovalRelay
    private var messageTask: Task<Void, Never>?

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

        default:
            break
        }
    }
}
#endif
