import Foundation
import Testing
import LancerCore
@testable import AppFeature

/// WT-B live-update regression: when a poll/relay delta flips turn status while
/// the thread stays open (no re-entry), derived chip / "Running" / background-
/// task state must flip to terminal without rebuilding the model.
///
/// `ShellLiveBridge` and `ConversationSyncCoordinator` are `#if os(iOS)` — they
/// do not run under plain macOS `swift test`. This suite exercises the same
/// pure derivation LiveThreadView / ThreadDetailView apply after a host-status
/// delta lands (`ChatTurn.Status.fromHostStatus` → in-place turn mutation →
/// `ToolChipGrouping.withTerminalTurnStatus` / `BackgroundTasksPresentation`).
@Suite("LiveTerminalStateRegression (WT-B)")
struct LiveTerminalStateRegressionTests {
    private let convID = "conv-wtb-live"
    private let turnID = "turn-wtb-live"
    private let runID = "run-wtb-live"
    private let toolUseID = "toolu_wtb_1"
    private let t0 = Date(timeIntervalSince1970: 3_000_000)

    // MARK: - Live open-thread model (mutable; no re-init)

    /// Mirrors the inputs LiveThreadView derives from: `bridge.transcriptTurns`
    /// + `eventsByTurnID`. Status updates mutate turns in place — the live path.
    private final class OpenThreadModel: @unchecked Sendable {
        var turns: [ChatTurn]
        var eventsByTurnID: [String: [ChatEvent]]

        init(turns: [ChatTurn], eventsByTurnID: [String: [ChatEvent]]) {
            self.turns = turns
            self.eventsByTurnID = eventsByTurnID
        }

        /// Same fail-closed rules as `ConversationSyncCoordinator.applyLastTurnStatusFromSummary`:
        /// map host status, only advance a still-`.running` local turn, never force
        /// terminal when the host still says running.
        func applyHostTurnStatus(turnID: String, hostStatus: String) {
            guard let idx = turns.firstIndex(where: { $0.id == turnID }) else { return }
            let mapped = ChatTurn.Status.fromHostStatus(hostStatus)
            guard turns[idx].status == .running else { return }
            guard mapped != .running else { return }
            turns[idx].status = mapped
            turns[idx].completedAt = turns[idx].completedAt ?? .now
        }
    }

    /// Derived UI state — same formula as LiveThreadView.liveToolChips /
    /// backgroundTaskRows and ThreadDetailView's WT-B call sites.
    private struct DerivedUI {
        let turnStatus: ChatTurn.Status
        let chips: [ToolChipItem]
        let backgroundRunningCount: Int

        /// Source of the chip "Running" badge (`ToolCallChipView.statusBadge`).
        var showsRunningChipLabel: Bool {
            chips.contains { $0.status == .running }
        }
    }

    private func deriveUI(from model: OpenThreadModel, turnID: String) -> DerivedUI? {
        guard let turn = model.turns.first(where: { $0.id == turnID }) else { return nil }
        let events = model.eventsByTurnID[turnID] ?? []
        let eventItems = TurnTranscriptAssembler.items(from: events)
        let turnIsTerminal = turn.status != .running
        let adjusted: [TurnTranscriptItem] = eventItems.map { item in
            guard case .toolChip(let chip) = item else { return item }
            let forced = ToolChipGrouping.withTerminalTurnStatus(
                [chip], turnIsTerminal: turnIsTerminal
            )
            return .toolChip(forced[0])
        }
        let chips = adjusted.compactMap { item -> ToolChipItem? in
            if case .toolChip(let chip) = item { return chip }
            return nil
        }
        let displayChips = ToolChipGrouping.withTerminalTurnStatus(
            chips, turnIsTerminal: turnIsTerminal
        )
        let rows = BackgroundTasksPresentation.rows(
            items: adjusted,
            events: events,
            artifacts: [],
            turnIsTerminal: turnIsTerminal
        )
        return DerivedUI(
            turnStatus: turn.status,
            chips: displayChips,
            backgroundRunningCount: BackgroundTasksPresentation.runningCount(in: rows)
        )
    }

    private func runningTurn() -> ChatTurn {
        ChatTurn(
            id: turnID,
            conversationID: convID,
            ordinal: 0,
            prompt: "run sleep",
            runID: runID,
            status: .running,
            assistantText: "starting tool"
        )
    }

    /// tool_call without tool_result → assembler leaves chip `.running` (WT-B leak).
    private func runningToolCallEvents() -> [ChatEvent] {
        [
            ChatEvent(
                conversationID: convID,
                seq: 1,
                turnID: turnID,
                runID: runID,
                kind: "output",
                text: "starting tool\n",
                createdAt: t0
            ),
            ChatEvent(
                conversationID: convID,
                seq: 2,
                turnID: turnID,
                runID: runID,
                kind: "tool_call",
                payloadJSON: #"{"name":"Bash","toolUseId":"\#(toolUseID)","input":{"command":"sleep 1"}}"#,
                createdAt: t0.addingTimeInterval(1)
            ),
        ]
    }

    private func makeOpenRunningModel() -> OpenThreadModel {
        OpenThreadModel(
            turns: [runningTurn()],
            eventsByTurnID: [turnID: runningToolCallEvents()]
        )
    }

    // MARK: - Tests

    @Test("live path: running turn + running chip → derived UI shows Running")
    func runningStateBeforeTerminal() {
        let model = makeOpenRunningModel()
        let ui = deriveUI(from: model, turnID: turnID)
        #expect(ui?.turnStatus == .running)
        #expect(ui?.showsRunningChipLabel == true)
        #expect(ui?.chips.contains(where: { $0.status == .running }) == true)
        #expect(ui?.backgroundRunningCount == 1)
        #expect(
            BackgroundTasksPresentation.pillLabel(runningCount: ui?.backgroundRunningCount ?? 0)
                == "1 running task"
        )
    }

    @Test("live path: host terminal delta (no re-init) flips turn + chips out of Running")
    func terminalDeltaFlipsDerivedStateWithoutRebuild() {
        let model = makeOpenRunningModel()
        let eventsBefore = model.eventsByTurnID[turnID] ?? []
        #expect(eventsBefore.count == 2)

        let before = deriveUI(from: model, turnID: turnID)
        #expect(before?.turnStatus == .running)
        #expect(before?.showsRunningChipLabel == true)

        // Poll/relay seam: host ledger says exited → fromHostStatus → in-place
        // mutation. Events stay put (no re-fetch / model rebuild).
        model.applyHostTurnStatus(turnID: turnID, hostStatus: "exited")

        #expect(model.turns.count == 1)
        #expect(model.turns[0].id == turnID)
        #expect(model.eventsByTurnID[turnID]?.count == eventsBefore.count)
        #expect(model.eventsByTurnID[turnID]?.map(\.seq) == eventsBefore.map(\.seq))

        let after = deriveUI(from: model, turnID: turnID)
        #expect(after?.turnStatus == .completed)
        #expect(after?.showsRunningChipLabel == false)
        #expect(after?.chips.contains(where: { $0.status == .running }) == false)
        #expect(after?.chips.allSatisfy({ $0.status == .done }) == true)
        #expect(after?.backgroundRunningCount == 0)
        #expect(
            BackgroundTasksPresentation.pillLabel(runningCount: after?.backgroundRunningCount ?? -1)
                == "0 running tasks"
        )

        // displayGroups path used by LiveThreadView.liveToolChips must agree.
        let turnIsTerminal = model.turns[0].status != .running
        let rawItems = TurnTranscriptAssembler.items(from: model.eventsByTurnID[turnID] ?? [])
        let grouped = ToolChipGrouping.displayGroups(
            from: rawItems,
            turnIsTerminal: turnIsTerminal
        )
        var groupedChips: [ToolChipItem] = []
        for item in grouped {
            if case .toolChips(let chips) = item {
                groupedChips.append(contentsOf: chips)
            }
        }
        #expect(!groupedChips.isEmpty)
        #expect(groupedChips.allSatisfy { $0.status != .running })
    }

    @Test("live path: completed host status also clears Running without re-entry")
    func completedHostStatusClearsRunning() {
        let model = makeOpenRunningModel()
        model.applyHostTurnStatus(turnID: turnID, hostStatus: "completed")
        let ui = deriveUI(from: model, turnID: turnID)
        #expect(ui?.turnStatus == .completed)
        #expect(ui?.showsRunningChipLabel == false)
        #expect(ui?.backgroundRunningCount == 0)
    }

    @Test("negative: still-running host status must not force chips terminal")
    func runningHostStatusDoesNotForceTerminal() {
        let model = makeOpenRunningModel()
        model.applyHostTurnStatus(turnID: turnID, hostStatus: "running")
        #expect(model.turns[0].status == .running)

        let ui = deriveUI(from: model, turnID: turnID)
        #expect(ui?.turnStatus == .running)
        #expect(ui?.showsRunningChipLabel == true)
        #expect(ui?.chips.contains(where: { $0.status == .running }) == true)
        #expect(ui?.backgroundRunningCount == 1)

        // needsApproval maps to .running — must also leave chips spinning.
        model.applyHostTurnStatus(turnID: turnID, hostStatus: "needsApproval")
        #expect(model.turns[0].status == .running)
        let still = deriveUI(from: model, turnID: turnID)
        #expect(still?.showsRunningChipLabel == true)
        #expect(still?.backgroundRunningCount == 1)
    }

    @Test("negative: withTerminalTurnStatus false keeps running chip (no forced terminal)")
    func mechanismDoesNotForceWhileTurnRunning() {
        let events = runningToolCallEvents()
        let items = TurnTranscriptAssembler.items(from: events)
        let chips = items.compactMap { item -> ToolChipItem? in
            if case .toolChip(let chip) = item { return chip }
            return nil
        }
        #expect(chips.count == 1)
        #expect(chips[0].status == .running)

        let kept = ToolChipGrouping.withTerminalTurnStatus(chips, turnIsTerminal: false)
        #expect(kept[0].status == .running)

        let forced = ToolChipGrouping.withTerminalTurnStatus(chips, turnIsTerminal: true)
        #expect(forced[0].status == .done)
    }

    /// FX10 path: pill fed by a still-`.running` ChatArtifact with no tool_result
    /// event. Host turn status alone must clear the running count (phone bug).
    @Test("live path: running relay artifact clears when host turn exits")
    func terminalDeltaClearsRunningRelayArtifact() {
        let model = OpenThreadModel(
            turns: [runningTurn()],
            eventsByTurnID: [turnID: []]
        )
        let artifact = ChatArtifact(
            id: toolUseID,
            conversationID: convID,
            turnID: turnID,
            runID: runID,
            kind: .tool,
            title: "Bash",
            payloadJSON: #"{"name":"Bash","toolUseId":"\#(toolUseID)","input":{"command":"sleep 1"}}"#,
            status: .running,
            createdAt: t0
        )

        func pillCount(turnIsTerminal: Bool) -> Int {
            let rows = BackgroundTasksPresentation.rows(
                items: [],
                events: model.eventsByTurnID[turnID] ?? [],
                artifacts: [artifact],
                turnIsTerminal: turnIsTerminal
            )
            return BackgroundTasksPresentation.runningCount(in: rows)
        }

        #expect(model.turns[0].status == .running)
        #expect(pillCount(turnIsTerminal: false) == 1)

        model.applyHostTurnStatus(turnID: turnID, hostStatus: "exited")
        #expect(model.turns[0].status == .completed)
        #expect(pillCount(turnIsTerminal: model.turns[0].status != .running) == 0)
    }
}
