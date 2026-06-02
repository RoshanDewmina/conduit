#if os(iOS)
import Foundation
import Observation
import AgentKit
import ConduitCore
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
                    passwordProvider: { throw ConduitError.authFailed(reason: "password auth requires interactive prompt") },
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

    public func createAgent(
        name: String,
        model: String,
        runtimeKind: HostedRuntimeKind,
        hostID: String,
        command: String
    ) async throws -> HostedAgent {
        guard hasCloudEntitlement else {
            throw AgentStoreError.entitlementRequired
        }
        let agent = HostedAgent(
            name: name,
            model: model,
            runtimeKind: runtimeKind,
            hostID: runtimeKind.requiresHostID ? hostID : (hostID.isEmpty ? nil : hostID),
            command: command
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
            run.logLines = [
                RunLogLine(text: "Run registered on control plane (\(agent.runtimeKind.displayName)). Cloud execution is orchestrated server-side.")
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
