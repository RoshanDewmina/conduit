#if os(iOS)
import Foundation
import LancerCore
import OSLog
import PersistenceKit
import SSHTransport

/// A command an AppIntent (Siri/Shortcuts) wants to apply, with no live SwiftUI
/// view or per-run `RunControlStore` in scope to resolve a transport itself.
public enum CommandRequest: Sendable {
    case respondApproval(id: String, decision: Approval.Decision, editedInput: String?)
    case pause(runId: String)
    case resume(runId: String)
    case cancel(runId: String)
    case queryStatus(homeDir: String?)
    /// Sends a resolved answer for a `.question` ChatArtifact (Lane E) — used
    /// by `AnswerQuestionIntent` (Siri voice-answer). `id` is the
    /// `ChatArtifact.id` the answer was resolved against, so the handler can
    /// re-fetch it and merge `answer` into its stored payload for local
    /// persistence. Entirely separate from `respondApproval`: this case must
    /// never gain an "approve" variant of any kind (see
    /// `DenyLatestApprovalIntent`'s doc comment) — questions and approvals
    /// are different artifacts with different risk profiles.
    case answerQuestion(id: String, answer: QuestionAnswerParams)
}

public enum CommandOutcome: Sendable, Equatable {
    case ok
    case statusSnapshot(AgentStatusSnapshot)
    case transportUnavailable
    case timedOut
    case denied(String)
}

/// The single UI-independent entry point for run-control (pause/resume/cancel)
/// and on-demand status queries — usable from contexts with no live view model
/// in scope, chiefly AppIntents. UI call sites that already hold a per-run
/// `RunControlStore`/`ActiveChatRun.channel` (`RunDetailView`, `NewChatTabView`)
/// keep using it directly: they're already transport-correct by construction
/// (built with either a connected `DaemonChannel` or a relay-bound
/// `RelayRunControl` at dispatch time) and don't need to re-resolve a transport
/// from a bare runId.
///
/// Approval decisions still route exclusively through `ApprovalRelay.enqueue` /
/// `forwardDecisionOnly` — the fallback-heavy, near-exactly-once path fixed by
/// the last relay bug-fix pass. This type never reimplements that logic, only
/// calls it, so there is exactly one place that knows how to route a decision.
///
/// Unlike approval delivery, pause/resume/cancel/status are NOT must-deliver:
/// a relay timeout does not fall through to a second transport attempt here —
/// silently retrying a slow/degraded bridge against a different transport could
/// apply the action to (or report status for) the wrong host.
@MainActor
public final class CommandGateway {
    public static let shared = CommandGateway(approvalRelay: .shared)

    private nonisolated static let logger = Logger(subsystem: "dev.lancer.mobile", category: "CommandGateway")

    private let approvalRelay: ApprovalRelay
    private let connectionStates: ConnectionStateStore

    /// Internal (not private) so tests can inject a fresh `ApprovalRelay` instance
    /// instead of mutating the shared singleton — mirrors `ApprovalRelay`'s own
    /// test convention (fresh instance + settable `channel`/`relayBridges`).
    /// `connectionStates` defaults to the app-wide store so Siri's connectivity
    /// answer is the same one Home/Fleet/Settings render.
    public init(approvalRelay: ApprovalRelay, connectionStates: ConnectionStateStore = .shared) {
        self.approvalRelay = approvalRelay
        self.connectionStates = connectionStates
    }

    /// The relay bridge for the first machine the authoritative store reports
    /// as connected. Tolerates a machine mid-reconnect with a short bounded
    /// wait (through the store's `.reconnecting`/`.hostOffline` states, not a
    /// bespoke poll) — the cold-launch race used to make Siri report a live
    /// machine as offline (fixed 2026-07-03 on the Siri branch with a local
    /// poll; this is the centralized replacement).
    private func firstConnectedBridge() async -> E2ERelayBridge? {
        guard let id = await connectionStates.waitForAnyConnected() else { return nil }
        return approvalRelay.relayBridges[id]
    }

    public func execute(_ request: CommandRequest) async -> CommandOutcome {
        switch request {
        case let .respondApproval(id, decision, editedInput):
            return await respondApproval(id: id, decision: decision, editedInput: editedInput)
        case let .pause(runId):
            return await sendRunControl(runId: runId, action: "pause")
        case let .resume(runId):
            return await sendRunControl(runId: runId, action: "resume")
        case let .cancel(runId):
            return await sendRunControl(runId: runId, action: "stop")
        case let .queryStatus(homeDir):
            return await queryStatus(homeDir: homeDir)
        case let .answerQuestion(id, answer):
            return await answerQuestion(id: id, answer: answer)
        }
    }

    // MARK: - Private

    /// Persists + audits + forwards a decision via `ApprovalRelay.enqueue`, the
    /// same path `ApprovalActionIntent` uses for a Live Activity tap. `editedInput`
    /// isn't threaded through `enqueue` (it always forwards `nil`) — no caller of
    /// this case needs an edit today (Siri only denies, never approves-with-edit;
    /// approve-with-edit stays a direct UI flow through `forwardDecisionOnly`).
    private func respondApproval(id: String, decision: Approval.Decision, editedInput: String?) async -> CommandOutcome {
        guard let db = try? AppDatabase.openShared() else { return .transportUnavailable }
        await approvalRelay.enqueue(approvalID: id, decision: decision, db: db, hostID: "")
        return .ok
    }

    /// Fire-and-forget run control (mirrors `E2ERelayBridge.sendRunControl`'s own
    /// contract: the daemon applies it if it recognizes `runId`, silently no-ops
    /// otherwise — status changes stream back separately over `agent.run.status`,
    /// there is no ack to await here). Tries the attached SSH channel first, then
    /// the relay bridge if paired.
    private func sendRunControl(runId: String, action: String) async -> CommandOutcome {
        if let channel = approvalRelay.channel {
            do {
                let ok: Bool
                switch action {
                case "pause": ok = try await channel.pauseRun(runId: runId)
                case "resume": ok = try await channel.resumeRun(runId: runId)
                default: ok = try await channel.cancelRun(runId: runId)
                }
                if ok { return .ok }
            } catch {
                Self.logger.warning("sendRunControl: SSH channel \(action, privacy: .public) failed for runId=\(runId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        // No machine context reaches here (an AppIntent has no per-run channel to
        // resolve from) — mirrors AppRoot's own "first active relay machine" fallback
        // used elsewhere for the same reason (e.g. loadWorkspaceFiles, resumeConversation).
        guard let bridge = await firstConnectedBridge() else {
            return .transportUnavailable
        }
        let sent = await bridge.sendRunControl(runId: runId, action: action)
        return sent ? .ok : .transportUnavailable
    }

    /// Queries status from the first available transport, in priority order: the
    /// attached SSH channel, then the relay bridge if paired. A relay timeout maps
    /// to `.timedOut` directly — it does not fall back to a channel that was
    /// already tried, and (per the type's doc comment) never cascades onto a
    /// different transport for a status read.
    private func queryStatus(homeDir: String?) async -> CommandOutcome {
        if let channel = approvalRelay.channel,
           let snap = try? await channel.fetchAgentStatus(homeDir: homeDir ?? "") {
            return .statusSnapshot(snap)
        }
        guard let bridge = await firstConnectedBridge() else {
            return .transportUnavailable
        }
        do {
            let snap = try await bridge.sendStatusQuery(homeDir: homeDir)
            return .statusSnapshot(snap)
        } catch E2EError.timedOut {
            return .timedOut
        } catch {
            Self.logger.warning("queryStatus: relay query failed: \(error.localizedDescription, privacy: .public)")
            return .transportUnavailable
        }
    }

    /// Sends a voice-answered question to the daemon (`AnswerQuestionIntent`'s
    /// confirmation-gated flow — see that type's doc comment) and mirrors the
    /// UI submit path's persistence step (`QuestionCardView`'s `onAnswer`)
    /// so the answered state survives relaunch even though this call has no
    /// live view model watching the artifact. Delivery failure short-circuits
    /// before persistence: if the daemon never received the answer, the
    /// local artifact should keep showing as pending rather than silently
    /// appear answered.
    private func answerQuestion(id: String, answer: QuestionAnswerParams) async -> CommandOutcome {
        guard await deliverQuestionAnswer(answer) else { return .transportUnavailable }
        await persistAnsweredQuestion(id: id, answer: answer)
        return .ok
    }

    /// Delivers a question answer via the connected transport, in the same
    /// priority order as `sendRunControl`/`queryStatus`: the attached SSH
    /// channel first, then the relay bridge if paired.
    private func deliverQuestionAnswer(_ answer: QuestionAnswerParams) async -> Bool {
        if let channel = approvalRelay.channel {
            do {
                try await channel.sendQuestionAnswer(answer)
                return true
            } catch {
                Self.logger.warning("answerQuestion: SSH channel send failed for questionId=\(answer.questionId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        guard let bridge = await firstConnectedBridge() else { return false }
        return await bridge.sendQuestionAnswer(answer)
    }

    /// Merges the sent answer into the artifact's stored payload and
    /// upserts it, matching `QuestionCardModel.mergeAnswer`'s contract used
    /// by the UI submit path. Best-effort: a failure here does not flip the
    /// reported `CommandOutcome` back to a failure — the daemon has already
    /// received the answer (the durable source of truth); only this
    /// device's local mirror would keep showing it as pending until the
    /// next sync.
    private func persistAnsweredQuestion(id: String, answer: QuestionAnswerParams) async {
        guard let db = try? AppDatabase.openShared() else { return }
        let repo = ChatConversationRepository(db)
        guard let artifact = try? await repo.artifact(id: id),
              let mergedJSON = QuestionCardModel.mergeAnswer(into: artifact.payloadJSON, answer: answer)
        else { return }
        var updated = artifact
        updated.payloadJSON = mergedJSON
        updated.status = .done
        try? await repo.upsertArtifact(updated)
    }
}
#endif
