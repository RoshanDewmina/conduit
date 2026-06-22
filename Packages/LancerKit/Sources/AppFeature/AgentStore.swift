#if os(iOS)
import Foundation
import Observation
import AgentKit
import LancerCore
import PersistenceKit
import SecurityKit
import SSHTransport
import SettingsFeature

/// Orchestrates hosted-agent CRUD, run lifecycle, and entitlement gating.
@MainActor @Observable
public final class AgentStore {
    public var agents: [HostedAgent] = []
    public var runsByAgent: [String: [AgentRun]] = [:]
    public var selectedRun: AgentRun?
    public var isLoading = false
    public var errorMessage: String?

    public var creditBalance: CreditBalance?
    public var quota: HostedQuotaSnapshot = HostedQuotaSnapshot()
    public var artifactsByRun: [String: [AgentArtifact]] = [:]
    public var schedulesByAgent: [String: [AgentSchedule]] = [:]
    public var orgMembers: [OrgMember] = []
    public var bridgeStatus: AgentStatusSnapshot?

    /// Backend-streamed log lines for cloud runs, keyed by runID. ssh-host runs
    /// populate `AgentRun.logLines` on-device instead; `logLines(for:)` merges them.
    public var runLogsByRun: [String: [RunLogLine]] = [:]
    private var runLogCursor: [String: Int] = [:]

    private var apiClient: HostedAgentAPIClient?
    private let apiBaseURL: URL?
    private let runtime: SSHHostRuntime
    private let purchaseManager: PurchaseManager
    private let backendConfigured: Bool

#if DEBUG
    private let debugStore = DebugHostedAgentStore.shared
#endif

    public init(
        backendURL: String,
        hostRepo: HostRepository,
        keyStore: KeyStore,
        hostKeyStore: HostKeyStore,
        purchaseManager: PurchaseManager = .shared
    ) {
        self.purchaseManager = purchaseManager
        self.backendConfigured = !backendURL.isEmpty
        if let url = URL(string: backendURL), !backendURL.isEmpty {
            self.apiBaseURL = url
            self.apiClient = HostedAgentAPIClient(baseURL: url, auth: Self.controlPlaneAuth())
        } else {
            self.apiBaseURL = nil
            self.apiClient = nil
        }

        self.runtime = SSHHostRuntime(
            resolveHost: { hostID in
                let hosts = try await hostRepo.all()
                return hosts.first { $0.id.uuidString == hostID }
            },
            hostKeyStore: hostKeyStore,
            credentials: { host in
                try await CredentialResolver.resolve(
                    authMethod: host.authMethod,
                    passwordProvider: { throw LancerError.authFailed(reason: "password auth requires interactive prompt") },
                    keyStore: keyStore
                )
            }
        )
    }

    public var hasCloudEntitlement: Bool {
        purchaseManager.hasCloudEntitlement
    }

    public var teamOrg: TeamOrgInfo? {
        purchaseManager.cloudEntitlement?.teamOrg
    }

    public func loadAgents() async {
        guard hasCloudEntitlement else {
            agents = []
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        refreshAPIClientAuth()
        do {
            if let apiClient, apiClient.isConfigured {
                agents = try await apiClient.listAgents()
            } else {
#if DEBUG
                agents = await debugStore.listAgents()
#else
                agents = []
#endif
            }
            recomputeQuota()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadBillingSnapshot() async {
        guard hasCloudEntitlement else { return }
        refreshAPIClientAuth()
        guard let apiClient, apiClient.isConfigured else {
            recomputeQuota()
            return
        }
        if let serverQuota = await apiClient.fetchQuota() {
            quota = serverQuota
        }
        do {
            creditBalance = try await apiClient.fetchCredits()
            quota.creditsRemainingUSD = creditBalance?.prepaidUSD
        } catch {
            creditBalance = nil
        }
        recomputeQuota()
    }

    public func refreshBridgeStatus(using channel: DaemonChannel) async {
        guard hasCloudEntitlement else { return }
        guard let snapshot = try? await channel.fetchAgentStatus() else { return }
        bridgeStatus = snapshot
        quota = snapshot.mergeIntoQuota(quota)
    }

    public func createAgent(
        name: String,
        model: String,
        runtimeKind: HostedRuntimeKind,
        hostID: String,
        command: String,
        workspacePath: String? = nil,
        region: String? = nil
    ) async throws -> HostedAgent {
        guard hasCloudEntitlement else {
            throw AgentStoreError.entitlementRequired
        }
        let trimmedWorkspace = workspacePath?.trimmingCharacters(in: .whitespaces)
        let agent = HostedAgent(
            name: name,
            model: model,
            runtimeKind: runtimeKind,
            hostID: runtimeKind.requiresHostID ? hostID : (hostID.isEmpty ? nil : hostID),
            command: command,
            workspacePath: (trimmedWorkspace?.isEmpty ?? true) ? nil : trimmedWorkspace,
            // Region only applies to cloud runtimes; ignore it for ssh-host.
            region: runtimeKind.isCloud ? region : nil
        )
        refreshAPIClientAuth()
        if let apiClient, apiClient.isConfigured {
            let created = try await apiClient.createAgent(agent)
            agents.append(created)
            recomputeQuota()
            return created
        }
#if DEBUG
        await debugStore.upsertAgent(agent)
        agents.append(agent)
        recomputeQuota()
        return agent
#else
        throw AgentStoreError.backendNotConfigured
#endif
    }

    public func startRun(agent: HostedAgent, prompt: String?) async throws -> AgentRun {
        guard hasCloudEntitlement else {
            throw AgentStoreError.entitlementRequired
        }

        var run: AgentRun
        refreshAPIClientAuth()
        if let apiClient, apiClient.isConfigured {
            run = try await apiClient.createRun(agentID: agent.id, prompt: prompt)
        } else {
#if DEBUG
            run = AgentRun(agentID: agent.id, prompt: prompt)
            await debugStore.upsertRun(run)
#else
            throw AgentStoreError.backendNotConfigured
#endif
        }

        if agent.runtimeKind.requiresHostID, agent.hostID != nil {
            let localRun = try await runtime.startRun(agent: agent, prompt: prompt)
            run.status = localRun.status
            run.logLines = localRun.logLines
            run.approvals = localRun.approvals
        } else {
            run.status = .running
            let regionSuffix = agent.region.map { " · region \($0)" } ?? ""
            run.logLines = [
                RunLogLine(text: "Run registered on control plane (cloud\(regionSuffix)). Execution is orchestrated server-side; logs stream here as they arrive.")
            ]
        }

        appendRun(run, for: agent.id)
        selectedRun = run
        recomputeQuota()
        return run
    }

    public func loadRuns(for agentID: String) async {
        guard hasCloudEntitlement else { return }
        refreshAPIClientAuth()
        do {
            if let apiClient, apiClient.isConfigured {
                runsByAgent[agentID] = try await apiClient.listRuns(agentID: agentID)
            } else {
#if DEBUG
                runsByAgent[agentID] = await debugStore.listRuns(agentID: agentID)
#endif
            }
            recomputeQuota()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func refreshRun(_ runID: String) async {
        do {
            let run = try await runtime.fetchRun(id: runID)
            if let agentID = runsByAgent.first(where: { $0.value.contains(where: { $0.id == runID }) })?.key {
                updateRun(run, agentID: agentID)
            }
            selectedRun = run
        } catch {
            refreshAPIClientAuth()
            if let apiClient, apiClient.isConfigured {
                if let run = try? await apiClient.fetchRun(id: runID) {
                    selectedRun = run
                    if let agentID = runsByAgent.first(where: { $0.value.contains(where: { $0.id == runID }) })?.key {
                        updateRun(run, agentID: agentID)
                    }
                }
            }
        }
    }

    public func loadArtifacts(runID: String) async {
        refreshAPIClientAuth()
        guard let apiClient, apiClient.isConfigured else { return }
        do {
            artifactsByRun[runID] = try await apiClient.listArtifacts(runID: runID)
        } catch {
            artifactsByRun[runID] = []
        }
    }

    /// Registers an artifact's metadata against a run and appends it to the local
    /// list. Bytes are stored out-of-band (SFTP on the ssh-host, GCS for cloud);
    /// `storageRef` points at that location.
    @discardableResult
    public func createArtifact(
        runID: String,
        name: String,
        storageRef: String,
        contentType: String? = nil,
        sizeBytes: Int64? = nil
    ) async throws -> AgentArtifact {
        refreshAPIClientAuth()
        guard let apiClient, apiClient.isConfigured else {
            throw AgentStoreError.backendNotConfigured
        }
        let artifact = try await apiClient.createArtifact(
            runID: runID,
            name: name,
            storageRef: storageRef,
            contentType: contentType,
            sizeBytes: sizeBytes
        )
        var list = artifactsByRun[runID] ?? []
        list.append(artifact)
        artifactsByRun[runID] = list
        return artifact
    }

    /// GET /runs/{id}/artifacts/{artifactId}/download — returns a signed download
    /// URL for cloud (GCS-backed) artifacts. Returns nil when the backend is
    /// unconfigured or the request fails.
    public func artifactDownloadURL(runID: String, artifactID: String) async -> URL? {
        refreshAPIClientAuth()
        guard let apiClient, apiClient.isConfigured else { return nil }
        return try? await apiClient.artifactDownloadURL(runID: runID, artifactID: artifactID)
    }

    /// Deletes an artifact (DELETE) and drops it from the local list.
    public func deleteArtifact(runID: String, artifactID: String) async throws {
        refreshAPIClientAuth()
        guard let apiClient, apiClient.isConfigured else {
            throw AgentStoreError.backendNotConfigured
        }
        try await apiClient.deleteArtifact(runID: runID, artifactID: artifactID)
        artifactsByRun[runID]?.removeAll { $0.id == artifactID }
    }

    // MARK: - ssh-host files (SFTP)

    /// Lists files in `path` on the agent's ssh-host over SFTP.
    public func listHostFiles(agent: HostedAgent, path: String) async throws -> [SFTPEntry] {
        try await runtime.listFiles(agent: agent, path: path)
    }

    /// Reads a remote file's bytes over SFTP (clamped to `limitBytes`).
    public func readHostFile(
        agent: HostedAgent,
        path: String,
        limitBytes: Int = 10 * 1024 * 1024
    ) async throws -> Data {
        try await runtime.readFile(agent: agent, path: path, limitBytes: limitBytes)
    }

    // MARK: - ssh-host workspace (git)

    /// Reads `git status` for the agent's configured workspace.
    public func workspaceStatus(agent: HostedAgent) async throws -> GitStatus {
        try await runtime.gitStatus(agent: agent)
    }

    /// Returns a unified diff for the workspace (optionally scoped to `path`).
    public func workspaceDiff(agent: HostedAgent, path: String? = nil) async throws -> String {
        try await runtime.gitDiff(agent: agent, path: path)
    }

    /// Creates and checks out a new branch in the workspace.
    public func workspaceCreateBranch(agent: HostedAgent, name: String) async throws {
        try await runtime.gitCreateBranch(agent: agent, name: name)
    }

    /// Stages all changes and commits them with `message`.
    public func workspaceCommitAll(agent: HostedAgent, message: String) async throws {
        try await runtime.gitCommitAll(agent: agent, message: message)
    }

    /// Pushes the current branch to origin.
    public func workspacePush(agent: HostedAgent) async throws {
        try await runtime.gitPush(agent: agent)
    }

    /// Opens a PR via `gh` and returns its URL.
    @discardableResult
    public func workspaceCreatePR(
        agent: HostedAgent,
        title: String,
        body: String,
        base: String? = nil
    ) async throws -> String {
        try await runtime.gitCreatePullRequest(agent: agent, title: title, body: body, base: base)
    }

    /// Registers a file produced on the agent's ssh-host as a run artifact: stats
    /// the remote file over SFTP to capture its size, then records the metadata in
    /// the control plane with `storageRef` pointing at the host path. The bytes
    /// stay on the host (no re-upload) — `storageRef` is how the host fetches them.
    @discardableResult
    public func uploadHostArtifact(
        runID: String,
        agent: HostedAgent,
        remotePath: String,
        name: String? = nil
    ) async throws -> AgentArtifact {
        let entry = try await runtime.statFile(agent: agent, path: remotePath)
        let artifactName = name ?? (remotePath as NSString).lastPathComponent
        return try await createArtifact(
            runID: runID,
            name: artifactName,
            storageRef: remotePath,
            contentType: HostedAgentAPIClient.inferContentType(for: artifactName),
            sizeBytes: entry.sizeBytes.map(Int64.init)
        )
    }

    /// Fetches any new backend log lines for a (typically cloud) run since the
    /// last cursor and appends them. No-op when the backend is unconfigured.
    public func loadNewRunLogs(runID: String) async {
        refreshAPIClientAuth()
        guard let apiClient, apiClient.isConfigured else { return }
        let since = runLogCursor[runID] ?? 0
        guard let page = try? await apiClient.fetchRunLogs(runID: runID, since: since) else { return }
        if !page.lines.isEmpty {
            var existing = runLogsByRun[runID] ?? []
            existing.append(contentsOf: page.lines)
            runLogsByRun[runID] = existing
        }
        runLogCursor[runID] = page.nextSince
    }

    /// Merged log source for a run: backend-streamed lines when present
    /// (cloud runs), otherwise the on-device lines (ssh-host runs).
    public func logLines(for runID: String, fallback: AgentRun) -> [RunLogLine] {
        let backend = runLogsByRun[runID] ?? []
        if !backend.isEmpty { return backend }
        if selectedRun?.id == runID { return selectedRun?.logLines ?? fallback.logLines }
        return fallback.logLines
    }

    public func loadSchedules(agentID: String) async {
        refreshAPIClientAuth()
        guard let apiClient, apiClient.isConfigured else { return }
        do {
            schedulesByAgent[agentID] = try await apiClient.listSchedules(agentID: agentID)
        } catch {
            schedulesByAgent[agentID] = []
        }
    }

    public func saveSchedule(agentID: String, cronExpr: String, command: String?) async throws {
        refreshAPIClientAuth()
        guard let apiClient, apiClient.isConfigured else {
            throw AgentStoreError.backendNotConfigured
        }
        let schedule = try await apiClient.createSchedule(
            agentID: agentID,
            cronExpr: cronExpr,
            command: command,
            enabled: true
        )
        var list = schedulesByAgent[agentID] ?? []
        list.append(schedule)
        schedulesByAgent[agentID] = list
    }

    /// Manually trigger a schedule now (POST /schedules/{id}/trigger).
    public func triggerSchedule(scheduleID: String, agentID: String) async throws {
        refreshAPIClientAuth()
        guard let apiClient, apiClient.isConfigured else {
            throw AgentStoreError.backendNotConfigured
        }
        let run = try await apiClient.triggerSchedule(scheduleID: scheduleID)
        appendRun(run, for: agentID)
        await loadSchedules(agentID: agentID)
        await loadBillingSnapshot()
    }

    /// Edits a schedule (PATCH). Only non-nil fields are changed; the returned
    /// schedule (with any recomputed nextRunAt) replaces the local copy.
    public func updateSchedule(
        scheduleID: String,
        agentID: String,
        cronExpr: String? = nil,
        command: String? = nil,
        enabled: Bool? = nil
    ) async throws {
        refreshAPIClientAuth()
        guard let apiClient, apiClient.isConfigured else {
            throw AgentStoreError.backendNotConfigured
        }
        let updated = try await apiClient.updateSchedule(
            scheduleID: scheduleID,
            cronExpr: cronExpr,
            command: command,
            enabled: enabled
        )
        replaceSchedule(updated, agentID: agentID)
    }

    /// Convenience enable/disable toggle (PATCH enabled only).
    public func toggleSchedule(scheduleID: String, agentID: String, enabled: Bool) async throws {
        try await updateSchedule(scheduleID: scheduleID, agentID: agentID, enabled: enabled)
    }

    /// Deletes a schedule (DELETE) and drops it from the local list.
    public func deleteSchedule(scheduleID: String, agentID: String) async throws {
        refreshAPIClientAuth()
        guard let apiClient, apiClient.isConfigured else {
            throw AgentStoreError.backendNotConfigured
        }
        try await apiClient.deleteSchedule(scheduleID: scheduleID)
        schedulesByAgent[agentID]?.removeAll { $0.id == scheduleID }
    }

    private func replaceSchedule(_ schedule: AgentSchedule, agentID: String) {
        var list = schedulesByAgent[agentID] ?? []
        if let idx = list.firstIndex(where: { $0.id == schedule.id }) {
            list[idx] = schedule
        } else {
            list.append(schedule)
        }
        schedulesByAgent[agentID] = list
    }

    // MARK: - Orgs / team

    /// Loads members for the entitlement's team org; no-op for individual customers.
    public func loadOrgMembers() async {
        guard let orgID = teamOrg?.orgId else {
            orgMembers = []
            return
        }
        refreshAPIClientAuth()
        guard let apiClient, apiClient.isConfigured else { return }
        do {
            orgMembers = try await apiClient.listOrgMembers(orgID: orgID)
        } catch {
            orgMembers = []
        }
    }

    public func inviteMember(email: String, role: String? = nil) async throws {
        guard let orgID = teamOrg?.orgId else {
            throw AgentStoreError.entitlementRequired
        }
        refreshAPIClientAuth()
        guard let apiClient, apiClient.isConfigured else {
            throw AgentStoreError.backendNotConfigured
        }
        let member = try await apiClient.inviteOrgMember(orgID: orgID, email: email, role: role)
        orgMembers.append(member)
    }

    // MARK: - Run cancel

    /// Cancels an active run. ssh-host runs execute on-device and are cancelled
    /// locally; cloud runs post a cancel request the runner honors (M6).
    public func cancelRun(runID: String, agent: HostedAgent) async {
        do {
            if agent.runtimeKind == .sshHost {
                try await runtime.cancelRun(id: runID)
            } else {
                refreshAPIClientAuth()
                guard let apiClient, apiClient.isConfigured else { return }
                try await apiClient.requestCancel(runID: runID)
            }
            await refreshRun(runID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - ssh-host interactive tools

    /// Streams output of an ad-hoc command on the agent's ssh-host. ssh-host only.
    public func execStream(agent: HostedAgent, command: String) -> AsyncThrowingStream<String, any Error> {
        runtime.execStream(agent: agent, command: command)
    }

    // MARK: - Billing portal

    /// Returns a Stripe customer-portal URL for managing the subscription, or nil
    /// when no customer id is known / backend is unconfigured.
    public func billingPortalURL() async -> URL? {
        refreshAPIClientAuth()
        guard
            let apiClient, apiClient.isConfigured,
            let customerId = UserDefaults.standard.string(forKey: PurchaseManager.stripeCustomerIDKey),
            !customerId.isEmpty
        else { return nil }
        return try? await apiClient.billingPortalURL(customerId: customerId, returnURL: nil)
    }

    /// POST /usage after managed OpenRouter (or other) AI calls.
    public func ingestUsage(_ record: UsageRecord, runID: String?, agentID: String?) async {
        if let runID, !runID.isEmpty, var run = selectedRun, run.id == runID {
            run.usageRecords.append(record)
            selectedRun = run
            if let agentID {
                updateRun(run, agentID: agentID)
            }
        }

        refreshAPIClientAuth()
        guard let apiClient, apiClient.isConfigured else { return }
        do {
            try await apiClient.reportUsage(
                runID: runID ?? "",
                agentID: agentID,
                record: record
            )
            await loadBillingSnapshot()
        } catch {
            // Best-effort metering — do not surface to UI.
        }
    }

    public func ingestOpenRouterUsage(client: OpenRouterClient, runID: String? = nil, agentID: String? = nil) async {
        let record = client.latestUsageRecord()
        guard record.totalTokens > 0 || (record.costUSD ?? 0) > 0 else { return }
        await ingestUsage(record, runID: runID, agentID: agentID)
    }

    public func respondToApproval(runID: String, approvalID: String, approved: Bool) async {
        do {
            try await runtime.respondToApproval(runID: runID, approvalID: approvalID, approved: approved)
            await refreshRun(runID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func monthlyCostLabel(for agent: HostedAgent) -> String {
        let runs = runsByAgent[agent.id] ?? []
        let total = runs.flatMap(\.usageRecords).compactMap(\.costUSD).reduce(0, +)
        guard total > 0 else { return "—" }
        return String(format: "$%.2f", total)
    }

    public func usageSpendTodayLabel() -> String {
        String(format: "$%.2f", quota.usageTodayUSD)
    }

    // MARK: - Private

    private static func controlPlaneAuth() -> ControlPlaneAuth {
        ControlPlaneAuth(
            customerId: UserDefaults.standard.string(forKey: PurchaseManager.stripeCustomerIDKey),
            appAccountToken: UserDefaults.standard.string(forKey: PurchaseManager.appAccountTokenKey),
            clientToken: UserDefaults.standard.string(forKey: PurchaseManager.clientTokenKey)
        )
    }

    private func refreshAPIClientAuth() {
        guard let apiBaseURL else { return }
        apiClient = HostedAgentAPIClient(baseURL: apiBaseURL, auth: Self.controlPlaneAuth())
    }

    private func recomputeQuota() {
        let allRuns = runsByAgent.values.flatMap { $0 }
        let today = Calendar.current.startOfDay(for: .now)
        let runsToday = allRuns.filter { $0.startedAt >= today }.count
        let activeRuns = allRuns.filter { !$0.status.isTerminal }.count
        let usageToday = allRuns.flatMap(\.usageRecords).compactMap(\.costUSD).reduce(0, +)

        quota.agentsUsed = agents.count
        quota.runsToday = runsToday
        quota.concurrentRuns = activeRuns
        quota.usageTodayUSD = usageToday
        if quota.creditsRemainingUSD == nil {
            quota.creditsRemainingUSD = creditBalance?.prepaidUSD
        }
    }

    private func appendRun(_ run: AgentRun, for agentID: String) {
        var runs = runsByAgent[agentID] ?? []
        runs.insert(run, at: 0)
        runsByAgent[agentID] = runs
#if DEBUG
        Task { await debugStore.upsertRun(run) }
#endif
    }

    private func updateRun(_ run: AgentRun, agentID: String) {
        var runs = runsByAgent[agentID] ?? []
        if let idx = runs.firstIndex(where: { $0.id == run.id }) {
            runs[idx] = run
        } else {
            runs.insert(run, at: 0)
        }
        runsByAgent[agentID] = runs
#if DEBUG
        Task { await debugStore.upsertRun(run) }
#endif
    }
}

#endif
