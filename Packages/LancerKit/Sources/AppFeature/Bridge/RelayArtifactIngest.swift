#if os(iOS)
import Foundation
import LancerCore
import PersistenceKit
import SessionFeature

/// Live tool artifacts over relay: the missing link between
/// `E2ERelayBridge.handleRelayMessage`'s `"agentArtifact"` case — which already
/// posts `lancerE2EArtifact` — and the chat mirror. Before this type, nothing
/// subscribed; Bash/`run_in_background` rows existed on the daemon ledger but
/// never reached `ChatConversationRepository`, so `BackgroundTasksPill` and
/// tool chips stayed empty (sweep #10 / #14, LD2 + LF-final).
///
/// Mirrors `ChatRunPersistenceSink.handleArtifact` (SSH path) and the
/// `RelayQuestionIngest` / `RelayApprovalIngest` notification→persist pattern.
@MainActor
public final class RelayArtifactIngest {
    private let chatRepo: ChatConversationRepository
    private var listenTask: Task<Void, Never>?

    public init(chatRepo: ChatConversationRepository) {
        self.chatRepo = chatRepo
    }

    /// Starts observing `lancerE2EArtifact`. Idempotent.
    public func start() {
        guard listenTask == nil else { return }
        listenTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: Notification.Name("lancerE2EArtifact")
            ) {
                guard let self else { return }
                await self.handle(notification)
            }
        }
    }

    private func handle(_ notification: Notification) async {
        guard let event = notification.userInfo?["params"] as? AgentArtifactEvent else { return }
        guard !event.runID.isEmpty, !event.artifactID.isEmpty else { return }
        guard let turn = try? await chatRepo.turnByRunID(event.runID) else { return }

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
        NotificationCenter.default.post(
            name: .lancerChatArtifactPersisted,
            object: nil,
            userInfo: ["conversationID": turn.conversationID]
        )
    }

    private static func persistablePayload(_ payload: String) -> String {
        let limit = 64 * 1024
        guard payload.utf8.count > limit else { return payload }
        return String(payload.prefix(limit)) + "\\n[artifact payload truncated]"
    }
}
#endif
