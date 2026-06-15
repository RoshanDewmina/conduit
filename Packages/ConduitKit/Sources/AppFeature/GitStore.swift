#if os(iOS)
import Foundation
import Observation
import ConduitCore
import DiffKit
import SSHTransport

/// Drives the per-run/loop "Changes" section + "Ship it" flow by calling the
/// conduitd `agent.git.*` RPCs on a host's `DaemonChannel`. Read paths (status /
/// diff / changed files) and the write path (ship) all route through conduitd so
/// every git write is audited + policy-gateable — not a direct-SSH bypass.
@MainActor @Observable
public final class GitStore {
    public var status: GitStatus?
    public var changedFiles: [Worktree.ChangedFile] = []
    public var diff: UnifiedDiff?
    public var isLoading = false
    public var isShipping = false
    public var error: String?
    /// Last ship outcome — drives the confirmation sheet's success/retry state.
    public var lastShip: GitShipResult?

    private let channel: DaemonChannel
    private let workdir: String

    public init(channel: DaemonChannel, workdir: String) {
        self.channel = channel
        self.workdir = workdir
    }

    public var hasChanges: Bool {
        if let status { return !status.isClean }
        return !changedFiles.isEmpty
    }

    /// Load branch/status + changed-file list for the workdir.
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        error = nil
        do {
            async let st = channel.gitStatus(workdir: workdir)
            async let files = channel.gitChangedFiles(workdir: workdir)
            status = try await st
            changedFiles = try await files
        } catch {
            self.error = (error as? DaemonChannelError).map(Self.describe) ?? error.localizedDescription
        }
    }

    /// Fetch + parse the full unified diff for the "Review diff" screen.
    @discardableResult
    public func loadDiff() async -> UnifiedDiff? {
        do {
            let text = try await channel.gitDiff(workdir: workdir)
            let parsed = UnifiedDiffParser.parse(text)
            diff = parsed
            return parsed
        } catch {
            self.error = (error as? DaemonChannelError).map(Self.describe) ?? error.localizedDescription
            return nil
        }
    }

    /// One-tap ship: stage + commit + push (+ open PR). Idempotent on the daemon
    /// side, so a retry after a partial failure is safe. Returns the result for
    /// the confirmation sheet to render precise success/partial/retry state.
    @discardableResult
    public func ship(
        message: String,
        openPR: Bool,
        base: String? = nil,
        title: String? = nil,
        body: String? = nil
    ) async -> GitShipResult? {
        isShipping = true
        defer { isShipping = false }
        error = nil
        do {
            let result = try await channel.gitShip(
                workdir: workdir,
                message: message,
                openPR: openPR,
                base: base,
                title: title ?? message,
                body: body ?? ""
            )
            lastShip = result
            // Surface a partial-failure message (push rejected / PR auth missing)
            // even though the RPC itself "succeeded" — the user must see it.
            if !result.isShipped || (openPR && result.prURL == nil), let msg = result.message, !msg.isEmpty {
                error = msg
            }
            // Reflect the new state (e.g. clean tree after a successful commit).
            await refresh()
            return result
        } catch {
            self.error = (error as? DaemonChannelError).map(Self.describe) ?? error.localizedDescription
            return nil
        }
    }

    private static func describe(_ e: DaemonChannelError) -> String {
        switch e {
        case .rpc(let m): return m
        case .notRunning: return "Host bridge not running"
        case .disconnected: return "Host disconnected"
        case .badResponse: return "Unexpected response from host"
        case .encodeFailed: return "Failed to encode request"
        }
    }
}
#endif
