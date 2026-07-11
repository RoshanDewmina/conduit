import Foundation
import LancerCore

public enum CursorTranscriptRow: Identifiable, Sendable {
    case turnSection(TurnSection)
    case bridgeErrorBanner(message: String)

    public struct TurnSection: Identifiable, Sendable {
        public let turnID: String
        public let prompt: String
        public let assistantText: String
        public let turnError: String?
        public let artifacts: [ChatArtifact]
        public let toolCallGroup: CursorToolCallGroup?
        public let liveOverlay: LiveOverlay?

        public struct LiveOverlay: Sendable {
            public let response: String?
            public let isWorking: Bool
            public let workingIndicator: CursorWorkingIndicator?

            public init(
                response: String?,
                isWorking: Bool,
                workingIndicator: CursorWorkingIndicator? = nil
            ) {
                self.response = response
                self.isWorking = isWorking
                self.workingIndicator = workingIndicator
            }
        }

        public var id: String { turnID }

        public init(
            turnID: String,
            prompt: String,
            assistantText: String,
            turnError: String?,
            artifacts: [ChatArtifact],
            toolCallGroup: CursorToolCallGroup? = nil,
            liveOverlay: LiveOverlay?
        ) {
            self.turnID = turnID
            self.prompt = prompt
            self.assistantText = assistantText
            self.turnError = turnError
            self.artifacts = artifacts
            self.toolCallGroup = toolCallGroup
            self.liveOverlay = liveOverlay
        }
    }

    public var id: String {
        switch self {
        case .turnSection(let section): section.id
        case .bridgeErrorBanner: "bridge-error-banner"
        }
    }
}

public enum CursorTranscriptMapper {
    public struct LiveOverlayInput: Sendable {
        public let isActive: Bool
        public let prompt: String
        public let response: String?
        public let isWorking: Bool

        public init(isActive: Bool, prompt: String, response: String?, isWorking: Bool) {
            self.isActive = isActive
            self.prompt = prompt
            self.response = response
            self.isWorking = isWorking
        }
    }

    public static func makeRows(
        turns: [ChatTurn],
        artifacts: [ChatArtifact],
        liveOverlay: LiveOverlayInput?,
        bridgeError: String?
    ) -> [CursorTranscriptRow] {
        let sortedTurns = turns.sorted { $0.ordinal < $1.ordinal }
        var rows: [CursorTranscriptRow] = []
        let matchedArtifactIDs = Set(
            sortedTurns.flatMap { turn in
                artifactsForTurn(turn, in: artifacts).map(\.id)
            }
        )
        let unmatchedArtifacts = artifacts.filter { !matchedArtifactIDs.contains($0.id) }

        // Ported from stablyai/orca (MIT):
        // src/renderer/src/components/native-chat/native-chat-pending.ts
        // (`prunePendingSends`/`pendingSendsAsMessages`) — an in-flight send is its
        // own synthetic row until the persisted transcript has *provably advanced
        // past it*, not merely because a turn already exists. Before this fix, a
        // live overlay was only ever rendered as a standalone "pending" row when
        // `sortedTurns` was completely empty (turn 1). On turn 2+ (`onContinue`),
        // the last PERSISTED turn is turn 1, so the overlay (carrying turn 2's new
        // prompt + in-flight response) got silently grafted onto turn 1's
        // `TurnSection` — which only forwards `response`/`isWorking`, never
        // `prompt` — so the new user bubble had nowhere to render and the
        // assistant text appeared stuck on turn 1's old content until the daemon
        // round-trip finished and a full reload pulled turn 2 from the ledger
        // (2026-07-09, "second message stale until reopen").
        let overlayIsNewPendingTurn = liveOverlay?.isActive == true
            && liveOverlay?.prompt != sortedTurns.last?.prompt

        if sortedTurns.isEmpty {
            if let overlay = liveOverlay, overlay.isActive {
                rows.append(.turnSection(makeSection(
                    turnID: "live-pending",
                    prompt: overlay.prompt,
                    assistantText: "",
                    turnError: nil,
                    artifacts: [],
                    liveOverlayInput: overlay
                )))
            }
        } else {
            for (index, turn) in sortedTurns.enumerated() {
                let isLast = index == sortedTurns.count - 1
                let overlayInput: LiveOverlayInput?
                if isLast, !overlayIsNewPendingTurn, let live = liveOverlay, live.isActive {
                    overlayInput = live
                } else {
                    overlayInput = nil
                }
                let turnArtifacts = artifactsForTurn(turn, in: artifacts)
                rows.append(.turnSection(makeSection(
                    turnID: turn.id,
                    prompt: turn.prompt,
                    assistantText: turn.assistantText,
                    turnError: turn.status == .failed ? turn.errorMessage : nil,
                    artifacts: turnArtifacts,
                    liveOverlayInput: overlayInput
                )))
            }

            if overlayIsNewPendingTurn, let live = liveOverlay {
                rows.append(.turnSection(makeSection(
                    turnID: "live-pending",
                    prompt: live.prompt,
                    assistantText: "",
                    turnError: nil,
                    artifacts: [],
                    liveOverlayInput: live
                )))
            }
        }

        if !unmatchedArtifacts.isEmpty, let lastTurn = sortedTurns.last {
            if case .turnSection(let section) = rows.last, section.turnID == lastTurn.id {
                let extraNonTool = unmatchedArtifacts.filter { $0.kind != .tool }
                let extraTools = unmatchedArtifacts.filter { $0.kind == .tool }
                let existingToolCards = section.toolCallGroup?.cards ?? []
                let mergedToolCards = existingToolCards
                    + CursorToolCallPresentation.cardsFromArtifacts(extraTools)
                let mergedGroup: CursorToolCallGroup? = mergedToolCards.isEmpty
                    ? nil
                    : CursorToolCallPresentation.makeGroup(cards: mergedToolCards)
                let updated = CursorTranscriptRow.TurnSection(
                    turnID: section.turnID,
                    prompt: section.prompt,
                    assistantText: section.assistantText,
                    turnError: section.turnError,
                    artifacts: section.artifacts + extraNonTool,
                    toolCallGroup: mergedGroup,
                    liveOverlay: section.liveOverlay
                )
                rows[rows.count - 1] = .turnSection(updated)
            }
        }

        if let bridgeError, !bridgeError.isEmpty {
            rows.append(.bridgeErrorBanner(message: bridgeError))
        }

        return rows
    }

    public static func liveOverlayInput(
        isRoutedThreadActive: Bool,
        prompt: String,
        response: String?,
        isWorking: Bool
    ) -> LiveOverlayInput? {
        guard isRoutedThreadActive else { return nil }
        return LiveOverlayInput(
            isActive: true,
            prompt: prompt,
            response: response,
            isWorking: isWorking
        )
    }

    // MARK: - Section assembly

    private static func makeSection(
        turnID: String,
        prompt: String,
        assistantText: String,
        turnError: String?,
        artifacts: [ChatArtifact],
        liveOverlayInput: LiveOverlayInput?
    ) -> CursorTranscriptRow.TurnSection {
        let toolArtifacts = artifacts.filter { $0.kind == .tool }
        let otherArtifacts = artifacts.filter { $0.kind != .tool }
        let group = toolGroup(from: toolArtifacts)
        let overlay = liveOverlayInput.map { live in
            resolveLiveOverlay(
                live: live,
                assistantText: assistantText,
                toolGroup: group
            )
        }
        return .init(
            turnID: turnID,
            prompt: prompt,
            assistantText: assistantText,
            turnError: turnError,
            artifacts: otherArtifacts,
            toolCallGroup: group,
            liveOverlay: overlay
        )
    }

    private static func toolGroup(from artifacts: [ChatArtifact]) -> CursorToolCallGroup? {
        let cards = CursorToolCallPresentation.cardsFromArtifacts(artifacts)
        guard !cards.isEmpty else { return nil }
        return CursorToolCallPresentation.makeGroup(cards: cards)
    }

    /// Resolve the live overlay's mutually exclusive working indicator.
    /// Visible streamed text suppresses the indicator (Orca rule).
    private static func resolveLiveOverlay(
        live: LiveOverlayInput,
        assistantText: String,
        toolGroup: CursorToolCallGroup?
    ) -> CursorTranscriptRow.TurnSection.LiveOverlay {
        let runningName = toolGroup?.cards.first(where: { $0.state == .running })?.name
        // Mutual exclusivity: if the smoother would show any text, hide the indicator.
        let displayText = CursorStreamingTextSmoother.resolvedDisplayText(
            overlayResponse: live.response,
            persistedAssistantText: assistantText
        )
        let indicator = CursorWorkingIndicator.resolve(
            isWorking: live.isWorking,
            hasVisibleText: !displayText.isEmpty,
            runningToolName: runningName,
            streamConnected: live.response != nil
        )
        return .init(
            response: live.response,
            isWorking: live.isWorking,
            workingIndicator: indicator
        )
    }

    private static func artifactsForTurn(_ turn: ChatTurn, in artifacts: [ChatArtifact]) -> [ChatArtifact] {
        artifacts.filter { artifact in
            if artifact.turnID == turn.id { return true }
            if artifact.runID == turn.runID { return true }
            return false
        }
    }
}
