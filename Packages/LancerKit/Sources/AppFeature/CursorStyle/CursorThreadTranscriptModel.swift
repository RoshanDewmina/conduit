#if os(iOS)
import Foundation
import Observation
import LancerCore
import PersistenceKit

@MainActor
@Observable
final class CursorThreadTranscriptModel {
    private(set) var rows: [CursorTranscriptRow] = []
    private(set) var conversationTitle: String?
    private(set) var isLoading = false

    private var conversationID: String?
    private var repository: ChatConversationRepository?
    private var turns: [ChatTurn] = []
    private var artifacts: [ChatArtifact] = []

    func configure(conversationID: String?) {
        guard self.conversationID != conversationID else { return }
        self.conversationID = conversationID
        turns = []
        artifacts = []
        conversationTitle = nil
        rows = []
        guard conversationID != nil else { return }
        repository = (try? AppDatabase.openShared()).map { ChatConversationRepository($0) }
        Task { await reload() }
    }

    func reload() async {
        guard let conversationID else {
            rows = []
            return
        }
        guard let repository else {
            rows = degradedRows()
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            conversationTitle = try await repository.conversation(id: conversationID)?.title
            turns = try await repository.turns(conversationID: conversationID)
            artifacts = try await repository.artifacts(conversationID: conversationID)
        } catch {
            turns = []
            artifacts = []
        }
        refreshRows(bridge: nil, bridgeError: nil, isActiveThread: false)
    }

    func refreshRows(
        bridge: CursorShellLiveBridge?,
        bridgeError: String?,
        isActiveThread: Bool
    ) {
        let overlay = liveOverlay(from: bridge, isActiveThread: isActiveThread)
        rows = CursorTranscriptMapper.makeRows(
            turns: turns,
            artifacts: artifacts,
            liveOverlay: overlay,
            bridgeError: bridgeError
        )
        if rows.isEmpty, let overlay, overlay.isActive {
            rows = CursorTranscriptMapper.makeRows(
                turns: [],
                artifacts: [],
                liveOverlay: overlay,
                bridgeError: bridgeError
            )
        } else if rows.isEmpty {
            rows = degradedRows(bridge: bridge, bridgeError: bridgeError)
        }
    }

    var lastPersistedPrompt: String? {
        turns.sorted { $0.ordinal < $1.ordinal }.last?.prompt
    }

    var lastTurnIsRunning: Bool {
        turns.sorted { $0.ordinal < $1.ordinal }.last?.status == .running
    }

    private func liveOverlay(
        from bridge: CursorShellLiveBridge?,
        isActiveThread: Bool
    ) -> CursorTranscriptMapper.LiveOverlayInput? {
        guard let bridge, isActiveThread else { return nil }
        // When working, pass "" (not nil) so the indicator can distinguish
        // "stream connected, awaiting first token" (streaming) from thinking.
        let response: String? = {
            if bridge.activeThreadIsWorking { return bridge.activeThreadResponse }
            return bridge.activeThreadResponse.isEmpty ? nil : bridge.activeThreadResponse
        }()
        return CursorTranscriptMapper.liveOverlayInput(
            isRoutedThreadActive: true,
            prompt: bridge.activeThreadPrompt,
            response: response,
            isWorking: bridge.activeThreadIsWorking
        )
    }

    private func degradedRows(
        bridge: CursorShellLiveBridge? = nil,
        bridgeError: String? = nil
    ) -> [CursorTranscriptRow] {
        guard let bridge else { return [] }
        let response: String? = {
            if bridge.activeThreadIsWorking { return bridge.activeThreadResponse }
            return bridge.activeThreadResponse.isEmpty ? nil : bridge.activeThreadResponse
        }()
        let overlay = CursorTranscriptMapper.liveOverlayInput(
            isRoutedThreadActive: true,
            prompt: bridge.activeThreadPrompt,
            response: response,
            isWorking: bridge.activeThreadIsWorking
        )
        return CursorTranscriptMapper.makeRows(
            turns: [],
            artifacts: bridge.activeThreadArtifacts,
            liveOverlay: overlay,
            bridgeError: bridgeError
        )
    }
}
#endif
