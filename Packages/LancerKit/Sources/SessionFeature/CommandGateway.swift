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

    /// Internal (not private) so tests can inject a fresh `ApprovalRelay` instance
    /// instead of mutating the shared singleton — mirrors `ApprovalRelay`'s own
    /// test convention (fresh instance + settable `channel`/`relayBridges`).
    public init(approvalRelay: ApprovalRelay) {
        self.approvalRelay = approvalRelay
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
        guard let bridge = approvalRelay.relayBridges.values.first(where: { $0.isActive }) else {
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
        guard let bridge = approvalRelay.relayBridges.values.first(where: { $0.isActive }) else {
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
}
#endif
