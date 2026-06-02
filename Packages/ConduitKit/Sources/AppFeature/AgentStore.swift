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

    private let apiClient: HostedAgentAPIClient?
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
            self.apiClient = HostedAgentAPIClient(baseURL: url, auth: Self.controlPlaneAuth())
        } else {
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

    public func loadAgents() async {
        guard hasCloudEntitlement else {
            agents = []
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func createAgent(
        name: String,
        model: String,
        hostID: String,
        command: String
    ) async throws -> HostedAgent {
        guard hasCloudEntitlement else {
            throw AgentStoreError.entitlementRequired
        }
        let agent = HostedAgent(
            name: name,
            model: model,
            runtimeKind: .sshHost,
            hostID: hostID,
            command: command
        )
        if let apiClient, apiClient.isConfigured {
            let created = try await apiClient.createAgent(agent)
            agents.append(created)
            return created
        }
#if DEBUG
        await debugStore.upsertAgent(agent)
        agents.append(agent)
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

        let localRun = try await runtime.startRun(agent: agent, prompt: prompt)
        run.status = localRun.status
        run.logLines = localRun.logLines
        run.approvals = localRun.approvals

        appendRun(run, for: agent.id)
        selectedRun = run
        return run
    }

    public func loadRuns(for agentID: String) async {
        guard hasCloudEntitlement else { return }
        do {
            if let apiClient, apiClient.isConfigured {
                runsByAgent[agentID] = try await apiClient.listRuns(agentID: agentID)
            } else {
#if DEBUG
                runsByAgent[agentID] = await debugStore.listRuns(agentID: agentID)
#endif
            }
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
            // Run may only exist server-side
            if let apiClient, apiClient.isConfigured {
                if let run = try? await apiClient.fetchRun(id: runID) {
                    selectedRun = run
                }
            }
        }
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

    // MARK: - Private

    private static func controlPlaneAuth() -> ControlPlaneAuth {
        ControlPlaneAuth(
            customerId: UserDefaults.standard.string(forKey: PurchaseManager.stripeCustomerIDKey),
            appAccountToken: UserDefaults.standard.string(forKey: PurchaseManager.appAccountTokenKey)
        )
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
