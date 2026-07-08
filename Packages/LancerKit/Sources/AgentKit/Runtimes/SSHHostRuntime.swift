import Foundation
import LancerCore
import SecurityKit
import SSHTransport

/// Executes hosted agents on a user SSH host via lancerd approvals + unified PTY.
public actor SSHHostRuntime: HostedAgentRuntime {
    public typealias HostResolver = @Sendable (String) async throws -> LancerCore.Host?
    public typealias SessionFactory = @Sendable (LancerCore.Host) -> SSHSession
    public typealias CredentialProvider = @Sendable (LancerCore.Host) async throws -> SSHCredential

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
        resolveHost: @escaping @Sendable (String) async throws -> LancerCore.Host?,
        hostKeyStore: HostKeyStore,
        makeSession: @escaping @Sendable (LancerCore.Host) -> SSHSession = { SSHSession(host: $0) },
        credentials: @escaping @Sendable (LancerCore.Host) async throws -> SSHCredential
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

        run.logLines.append(RunLogLine(text: "lancerd connected on \(host.name)"))

        let command = agent.command ?? "echo 'no command configured'"
        if let prompt, !prompt.isEmpty {
            run.logLines.append(RunLogLine(text: "$ \(command) — \(prompt.prefix(80))"))
        } else {
            run.logLines.append(RunLogLine(text: "$ \(command)"))
        }
        run.logLines.append(RunLogLine(text: "Awaiting agent output via lancerd hooks…"))

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

    /// One-shot interactive command execution against the agent's ssh-host,
    /// streaming combined stdout/stderr as text. Uses `SSHSession.execute` (a
    /// command channel — not the block-terminal PTY) on a dedicated session that
    /// is torn down when the stream ends or the consumer cancels. ssh-host only.
    public nonisolated func execStream(agent: HostedAgent, command: String) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard agent.runtimeKind == .sshHost else {
                        throw HostedAgentRuntimeError.unsupportedRuntime(agent.runtimeKind)
                    }
                    guard let hostID = agent.hostID else {
                        throw HostedAgentRuntimeError.hostNotFound("missing hostID")
                    }
                    let (session, _) = try await self.openSession(hostID: hostID)
                    defer { Task { await session.disconnect() } }
                    let stream = try await session.execute(command)
                    for try await (data, _) in stream {
                        try Task.checkCancellation()
                        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Resolves a host id, builds a session, and connects it (TOFU host-key
    /// validation applies). Shared by exec/files/workspace helpers.
    func openSession(hostID: String) async throws -> (SSHSession, LancerCore.Host) {
        guard let host = try await resolveHost(hostID) else {
            throw HostedAgentRuntimeError.hostNotFound(hostID)
        }
        let session = makeSession(host)
        let credential = try await credentials(host)
        try await session.connect(credential: credential, hostKeyStore: hostKeyStore)
        return (session, host)
    }

    // MARK: - SFTP file operations (ssh-host only)

    /// Lists directory entries on the agent's ssh-host over SFTP.
    public func listFiles(agent: HostedAgent, path: String) async throws -> [SFTPEntry] {
        try await withSFTPClient(agent: agent) { try await $0.list(path: path) }
    }

    /// Reads up to `limitBytes` of a remote file over SFTP.
    public func readFile(
        agent: HostedAgent,
        path: String,
        limitBytes: Int = 10 * 1024 * 1024
    ) async throws -> Data {
        try await withSFTPClient(agent: agent) {
            try await $0.read(path: path, limitBytes: limitBytes)
        }
    }

    /// Stats a single remote file/dir over SFTP (used to size artifacts).
    public func statFile(agent: HostedAgent, path: String) async throws -> SFTPEntry {
        try await withSFTPClient(agent: agent) { try await $0.stat(path: path) }
    }

    /// Writes `data` to a remote path over SFTP, replacing any existing file.
    public func writeFile(agent: HostedAgent, path: String, data: Data) async throws {
        try await withSFTPClient(agent: agent) { try await $0.write(path: path, data: data) }
    }

    /// Uploads a local file to a remote path over SFTP.
    public func uploadFile(agent: HostedAgent, localFileURL: URL, to remotePath: String) async throws {
        try await withSFTPClient(agent: agent) {
            try await $0.upload(localFileURL: localFileURL, to: remotePath)
        }
    }

    /// Removes a remote file over SFTP.
    public func deleteFile(agent: HostedAgent, path: String) async throws {
        try await withSFTPClient(agent: agent) { try await $0.remove(path: path) }
    }

    /// Opens a session for the agent's ssh-host, builds an `SFTPClient`, runs
    /// `body`, and tears the session down — mirroring `execStream`'s one-shot
    /// lifecycle so no long-lived SFTP handle is held. ssh-host only.
    private func withSFTPClient<T: Sendable>(
        agent: HostedAgent,
        _ body: (SFTPClient) async throws -> T
    ) async throws -> T {
        guard agent.runtimeKind == .sshHost else {
            throw HostedAgentRuntimeError.unsupportedRuntime(agent.runtimeKind)
        }
        guard let hostID = agent.hostID else {
            throw HostedAgentRuntimeError.hostNotFound("missing hostID")
        }
        let (session, _) = try await openSession(hostID: hostID)
        defer { Task { await session.disconnect() } }
        return try await body(SFTPClient(session: session))
    }

    // MARK: - Workspace git operations (ssh-host only)

    /// Reads `git status` for the agent's workspace.
    public func gitStatus(agent: HostedAgent, workdir: String? = nil) async throws -> GitStatus {
        try await withGitClient(agent: agent, workdir: workdir) { git, dir in
            try await git.status(workdir: dir)
        }
    }

    /// Returns a unified diff for the workspace (optionally scoped to `path`).
    public func gitDiff(
        agent: HostedAgent,
        workdir: String? = nil,
        path: String? = nil,
        staged: Bool = false
    ) async throws -> String {
        try await withGitClient(agent: agent, workdir: workdir) { git, dir in
            try await git.diff(workdir: dir, path: path, staged: staged)
        }
    }

    /// Creates and checks out a new branch in the workspace.
    public func gitCreateBranch(agent: HostedAgent, workdir: String? = nil, name: String) async throws {
        try await withGitClient(agent: agent, workdir: workdir) { git, dir in
            try await git.createBranch(workdir: dir, name: name)
        }
    }

    /// Stages all changes and commits them with `message`.
    public func gitCommitAll(agent: HostedAgent, workdir: String? = nil, message: String) async throws {
        try await withGitClient(agent: agent, workdir: workdir) { git, dir in
            try await git.stage(workdir: dir)
            try await git.commit(workdir: dir, message: message)
        }
    }

    /// Pushes the current branch to origin (setting upstream).
    public func gitPush(agent: HostedAgent, workdir: String? = nil) async throws {
        try await withGitClient(agent: agent, workdir: workdir) { git, dir in
            try await git.push(workdir: dir)
        }
    }

    /// Opens a PR via `gh` and returns its URL.
    public func gitCreatePullRequest(
        agent: HostedAgent,
        workdir: String? = nil,
        title: String,
        body: String,
        base: String? = nil
    ) async throws -> String {
        try await withGitClient(agent: agent, workdir: workdir) { git, dir in
            try await git.createPullRequest(workdir: dir, title: title, body: body, base: base)
        }
    }

    /// Resolves the workspace directory (explicit `workdir` override →
    /// `agent.workspacePath`), opens a one-shot session, builds a `GitClient`,
    /// runs `body`, and tears the session down. Throws when no workspace path is
    /// configured. ssh-host only.
    private func withGitClient<T: Sendable>(
        agent: HostedAgent,
        workdir: String?,
        _ body: (GitClient, String) async throws -> T
    ) async throws -> T {
        guard agent.runtimeKind == .sshHost else {
            throw HostedAgentRuntimeError.unsupportedRuntime(agent.runtimeKind)
        }
        guard let hostID = agent.hostID else {
            throw HostedAgentRuntimeError.hostNotFound("missing hostID")
        }
        let resolved = workdir ?? agent.workspacePath
        guard let dir = resolved, !dir.isEmpty else {
            throw HostedAgentRuntimeError.workspaceNotConfigured
        }
        let (session, _) = try await openSession(hostID: hostID)
        defer { Task { await session.disconnect() } }
        return try await body(GitClient(session: session), dir)
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
            case .agentStatus, .secretRequest, .runOutput, .runStatus, .runReceipt, .artifact, .sessionDiscovered, .pong, .unknown:
                break
            case .toolStart:
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
