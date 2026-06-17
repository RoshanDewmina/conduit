import Foundation
import Observation

// Named RunControlStatus (not RunStatus) to avoid colliding with AgentKit.RunStatus,
// which is also visible in AppFeature.
public enum RunControlStatus: Equatable, Sendable {
    case running, paused, stopped
    // Set when the daemon stops a run for exceeding its budget. The store reaches this
    // via the daemon event-stream wiring (Task 6+), not a synchronous control call.
    case budgetExceeded
}

/// The run-control surface the store depends on. DaemonChannel will conform in Task 6;
/// faked in tests. Sendable so it can cross the MainActor boundary safely.
public protocol RunControlling: Sendable {
    func pauseRun(runId: String) async throws -> Bool
    func resumeRun(runId: String) async throws -> Bool
    func stopRun(runId: String) async throws -> Bool
    func setRunBudget(runId: String, budgetUSD: Double) async throws -> Bool
}

@MainActor
@Observable
public final class RunControlStore {
    public private(set) var status: RunControlStatus
    public private(set) var lastError: String?

    private let channel: any RunControlling
    private let runId: String

    public init(channel: any RunControlling, runId: String, status: RunControlStatus = .running) {
        self.channel = channel
        self.runId = runId
        self.status = status
    }

    /// Stop is available while a run is live (running or paused).
    public var canStop: Bool { status == .running || status == .paused }
    /// Pause only applies to a currently running run.
    public var canPause: Bool { status == .running }
    /// Resume only applies to a paused run.
    public var canResume: Bool { status == .paused }
    /// Budget can be adjusted while the run is live.
    public var canSetBudget: Bool { status == .running || status == .paused }

    public func pause() async {
        await run {
            if try await channel.pauseRun(runId: runId) { status = .paused }
        }
    }

    public func resume() async {
        await run {
            if try await channel.resumeRun(runId: runId) { status = .running }
        }
    }

    public func stop() async {
        await run {
            if try await channel.stopRun(runId: runId) { status = .stopped }
        }
    }

    public func setBudget(_ usd: Double) async {
        await run {
            _ = try await channel.setRunBudget(runId: runId, budgetUSD: usd)
        }
    }

    private func run(_ op: () async throws -> Void) async {
        lastError = nil
        do {
            try await op()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
