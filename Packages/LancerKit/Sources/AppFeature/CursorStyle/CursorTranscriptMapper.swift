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
        public let liveOverlay: LiveOverlay?

        public struct LiveOverlay: Sendable {
            public let response: String?
            public let isWorking: Bool
        }

        public var id: String { turnID }
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
                rows.append(.turnSection(.init(
                    turnID: "live-pending",
                    prompt: overlay.prompt,
                    assistantText: "",
                    turnError: nil,
                    artifacts: [],
                    liveOverlay: .init(response: overlay.response, isWorking: overlay.isWorking)
                )))
            }
        } else {
            for (index, turn) in sortedTurns.enumerated() {
                let isLast = index == sortedTurns.count - 1
                let overlay: CursorTranscriptRow.TurnSection.LiveOverlay?
                if isLast, !overlayIsNewPendingTurn, let live = liveOverlay, live.isActive {
                    overlay = .init(response: live.response, isWorking: live.isWorking)
                } else {
                    overlay = nil
                }
                rows.append(.turnSection(.init(
                    turnID: turn.id,
                    prompt: turn.prompt,
                    assistantText: turn.assistantText,
                    turnError: turn.status == .failed ? turn.errorMessage : nil,
                    artifacts: artifactsForTurn(turn, in: artifacts),
                    liveOverlay: overlay
                )))
            }

            if overlayIsNewPendingTurn, let live = liveOverlay {
                rows.append(.turnSection(.init(
                    turnID: "live-pending",
                    prompt: live.prompt,
                    assistantText: "",
                    turnError: nil,
                    artifacts: [],
                    liveOverlay: .init(response: live.response, isWorking: live.isWorking)
                )))
            }
        }

        if !unmatchedArtifacts.isEmpty, let lastTurn = sortedTurns.last {
            if case .turnSection(let section) = rows.last, section.turnID == lastTurn.id {
                let updated = CursorTranscriptRow.TurnSection(
                    turnID: section.turnID,
                    prompt: section.prompt,
                    assistantText: section.assistantText,
                    turnError: section.turnError,
                    artifacts: section.artifacts + unmatchedArtifacts,
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

    private static func artifactsForTurn(_ turn: ChatTurn, in artifacts: [ChatArtifact]) -> [ChatArtifact] {
        artifacts.filter { artifact in
            if artifact.turnID == turn.id { return true }
            if artifact.runID == turn.runID { return true }
            return false
        }
    }
}
