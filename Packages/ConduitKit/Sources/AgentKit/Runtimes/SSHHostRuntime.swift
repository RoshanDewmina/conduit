import Foundation
import ConduitCore
import SecurityKit
import SSHTransport

/// Executes hosted agents on a user SSH host via conduitd approvals + unified PTY.
public actor SSHHostRuntime: HostedAgentRuntime {
    public typealias HostResolver = @Sendable (String) async throws -> ConduitCore.Host?
    public typealias SessionFactory = @Sendable (ConduitCore.Host) -> SSHSession
    public typealias CredentialProvider = @Sendable (ConduitCore.Host) async throws -> SSHCredential

    private let resolveHost: HostResolver
    private let makeSession: SessionFactory
    private let credentials: CredentialProvider
    private let hostKeyStore: HostKeyStore
    private var activeRuns: [String: ActiveRun] = [:]

    private struct ActiveRun {
        var run: AgentRun
        var channel: DaemonChannel?
        var monitorTask: Task<Void, Never>?
    }

    public init(
        resolveHost: @escaping @Sendable (String) async throws -> ConduitCore.Host?,
        hostKeyStore: HostKeyStore,
        makeSession: @escaping @Sendable (ConduitCore.Host) -> SSHSession = { SSHSession(host: $0) },
        credentials: @escaping @Sendable (ConduitCore.Host) async throws -> SSHCredential
    ) {
        self.resolveHost = resolveHost
        self.hostKeyStore = hostKeyStore
        self.makeSession = makeSession
        self.credentials = credentials
    }

    public func startRun(agent: HostedAgent, prompt: String?) async throws -> AgentRun {
        guard agent.runtimeKind == .sshHost else {
            throw HostedAgentRuntimeError.unsupportedRuntime(agent.runtimeKind)
        }
        guard let hostID = agent.hostID else {
            throw HostedAgentRuntimeError.hostNotFound("missing hostID")
        }
        guard let host = try await resolveHost(hostID) else {
            throw HostedAgentRuntimeError.hostNotFound(hostID)
        }

        var run = AgentRun(
            agentID: agent.id,
            status: .running,
            prompt: prompt,
            logLines: [RunLogLine(text: "Connecting to \(host.displayAddress)…")]
        )

        let session = makeSession(host)
        let credential = try await credentials(host)
        try await session.connect(credential: credential, hostKeyStore: hostKeyStore)

        let channel = DaemonChannel(session: session)
        try await channel.start()

        run.logLines.append(RunLogLine(text: "conduitd connected on \(host.name)"))

        let command = agent.command ?? "echo 'no command configured'"
        if let prompt, !prompt.isEmpty {
            run.logLines.append(RunLogLine(text: "$ \(command) — \(prompt.prefix(80))"))
        } else {
            run.logLines.append(RunLogLine(text: "$ \(command)"))
        }
        run.logLines.append(RunLogLine(text: "Awaiting agent output via conduitd hooks…"))

        activeRuns[run.id] = ActiveRun(run: run, channel: channel, monitorTask: nil)

        let runID = run.id
        Task { [weak channel] in
            await self.monitorEvents(runID: runID, channel: channel)
        }

        return run
    }

    public func fetchRun(id: String) async throws -> AgentRun {
        guard let active = activeRuns[id] else {
            throw HostedAgentRuntimeError.runNotFound(id)
        }
        return active.run
    }

    public func cancelRun(id: String) async throws {
        guard var active = activeRuns[id] else {
            throw HostedAgentRuntimeError.runNotFound(id)
        }
        active.monitorTask?.cancel()
        await active.channel?.stop()
        active.run.status = .cancelled
        active.run.endedAt = .now
        activeRuns[id] = active
    }

    public func respondToApproval(runID: String, approvalID: String, approved: Bool) async throws {
        guard let active = activeRuns[runID], let channel = active.channel else {
            throw HostedAgentRuntimeError.runNotFound(runID)
        }
        let decision: Approval.Decision = approved ? .approved : .rejected
        try await channel.respond(approvalId: approvalID, decision: decision)
        updateApproval(runID: runID, approvalID: approvalID, approved: approved)
    }

    // MARK: - Private

    private func monitorEvents(runID: String, channel: DaemonChannel?) async {
        guard let channel else { return }
        for await event in await channel.events {
            switch event {
            case .approvalPending(let params):
                appendApproval(runID: runID, params: params)
            case .pong, .unknown:
                break
            }
        }
        await channel.stop()
        finalizeRun(runID: runID, succeeded: true)
    }

    private func appendApproval(runID: String, params: ApprovalPendingParams) {
        guard var active = activeRuns[runID] else { return }
        let approval = RunApproval(
            id: params.id,
            kind: params.kind,
            command: params.command,
            status: .pending
        )
        active.run.approvals.append(approval)
        active.run.status = .awaitingApproval
        active.run.logLines.append(RunLogLine(text: "Approval requested: \(params.kind)"))
        activeRuns[runID] = active
    }

    private func updateApproval(runID: String, approvalID: String, approved: Bool) {
        guard var active = activeRuns[runID] else { return }
        if let idx = active.run.approvals.firstIndex(where: { $0.id == approvalID }) {
            active.run.approvals[idx].status = approved ? .approved : .rejected
        }
        if active.run.approvals.allSatisfy({ $0.status != .pending }) {
            active.run.status = .running
        }
        activeRuns[runID] = active
    }

    private func finalizeRun(runID: String, succeeded: Bool) {
        guard var active = activeRuns[runID] else { return }
        active.run.status = succeeded ? .succeeded : .failed
        active.run.endedAt = .now
        active.run.logLines.append(RunLogLine(text: succeeded ? "Run completed." : "Run failed."))
        activeRuns[runID] = active
    }
}
