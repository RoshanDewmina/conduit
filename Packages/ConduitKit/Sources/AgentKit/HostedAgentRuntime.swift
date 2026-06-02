import Foundation
import ConduitCore

// MARK: - Runtime protocol

/// Cloud-agnostic adapter that executes a hosted agent on a compute target.
public protocol HostedAgentRuntime: Sendable {
    func startRun(agent: HostedAgent, prompt: String?) async throws -> AgentRun
    func fetchRun(id: String) async throws -> AgentRun
    func cancelRun(id: String) async throws
    func respondToApproval(runID: String, approvalID: String, approved: Bool) async throws
}

public enum HostedAgentRuntimeError: Error, Sendable, Equatable {
    case unsupportedRuntime(HostedRuntimeKind)
    case hostNotFound(String)
    case runNotFound(String)
    case notConnected
}

public enum AgentStoreError: Error, Sendable, Equatable {
    case entitlementRequired
    case backendNotConfigured
}

// MARK: - Control-plane API

/// Stripe / app-account identifiers required by push-backend entitlement checks.
public struct ControlPlaneAuth: Sendable, Equatable {
    public var customerId: String?
    public var appAccountToken: String?

    public init(customerId: String? = nil, appAccountToken: String? = nil) {
        self.customerId = customerId
        self.appAccountToken = appAccountToken
    }
}

/// REST client for hosted-agent definitions and run metadata (push-backend).
public struct HostedAgentAPIClient: Sendable {
    public let baseURL: URL
    private let auth: ControlPlaneAuth
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(baseURL: URL, auth: ControlPlaneAuth = ControlPlaneAuth(), session: URLSession = .shared) {
        self.baseURL = baseURL
        self.auth = auth
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    public var isConfigured: Bool {
        !baseURL.absoluteString.isEmpty
    }

    // MARK: Agents

    public func listAgents() async throws -> [HostedAgent] {
        let response: AgentsListResponse = try await get("agents")
        return response.agents.map(mapAgent)
    }

    public func createAgent(_ agent: HostedAgent) async throws -> HostedAgent {
        let body = CreateAgentBody(
            name: agent.name,
            runtime: Self.mapRuntime(agent.runtimeKind),
            config: .init(model: agent.model, hostID: agent.hostID ?? "", command: agent.command ?? "")
        )
        let created: BackendAgent = try await post("agents", body: body)
        return mapAgent(created)
    }

    // MARK: Runs

    public func listRuns(agentID: String) async throws -> [AgentRun] {
        let response: RunsListResponse = try await get("runs?agentId=\(agentID)")
        return response.runs.map(mapRun)
    }

    public func createRun(agentID: String, prompt: String?) async throws -> AgentRun {
        let body = CreateRunBody(agentId: agentID, command: prompt)
        let created: BackendRun = try await post("runs", body: body)
        return mapRun(created)
    }

    public func fetchRun(id: String) async throws -> AgentRun {
        let run: BackendRun = try await get("runs/\(id)")
        return mapRun(run)
    }

    public func reportUsage(runID: String, agentID: String?, record: UsageRecord) async throws {
        let body = UsageIngestBody(
            runId: runID,
            agentId: agentID,
            model: record.model,
            tokensIn: record.inputTokens,
            tokensOut: record.outputTokens,
            cost: record.costUSD ?? 0
        )
        _ = try await post("usage", body: body, as: UsageIngestResponse.self)
    }

    // MARK: - DTO mapping (testable)

    static func mapAgent(_ backend: BackendAgent) -> HostedAgent {
        HostedAgent(
            id: backend.id,
            name: backend.name,
            model: backend.config?.model ?? "anthropic/claude-sonnet-4",
            runtimeKind: mapRuntimeKind(backend.runtime),
            hostID: backend.config?.hostID,
            command: backend.config?.command,
            createdAt: parseRFC3339(backend.createdAt) ?? .now,
            updatedAt: parseRFC3339(backend.updatedAt) ?? .now
        )
    }

    static func mapRun(_ backend: BackendRun) -> AgentRun {
        AgentRun(
            id: backend.id,
            agentID: backend.agentId,
            status: RunStatus(rawValue: backend.status) ?? .pending,
            prompt: backend.command,
            startedAt: parseRFC3339(backend.startedAt ?? backend.createdAt) ?? .now,
            endedAt: parseRFC3339(backend.completedAt)
        )
    }

    static func mapRuntimeKind(_ runtime: String) -> HostedRuntimeKind {
        switch runtime {
        case "fly": .fly
        default: .sshHost
        }
    }

    static func mapRuntime(_ kind: HostedRuntimeKind) -> String {
        switch kind {
        case .sshHost: "ssh-host"
        case .fly: "fly"
        }
    }

    static func parseRFC3339(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: value)
    }

    // MARK: - HTTP helpers

    private struct AgentsListResponse: Decodable { let agents: [BackendAgent] }
    private struct RunsListResponse: Decodable { let runs: [BackendRun] }
    private struct UsageIngestResponse: Decodable { let id: String }

    struct BackendAgent: Decodable, Equatable {
        let id: String
        let name: String
        let runtime: String
        let config: BackendAgentConfig?
        let createdAt: String?
        let updatedAt: String?
    }

    struct BackendAgentConfig: Decodable, Equatable {
        let model: String?
        let hostID: String?
        let command: String?
    }

    struct BackendRun: Decodable, Equatable {
        let id: String
        let agentId: String
        let status: String
        let command: String?
        let startedAt: String?
        let completedAt: String?
        let createdAt: String?
    }

    private struct CreateAgentBody: Encodable {
        let name: String
        let runtime: String
        let config: Config

        struct Config: Encodable {
            let model: String
            let hostID: String
            let command: String
        }
    }

    private struct CreateRunBody: Encodable {
        let agentId: String
        let command: String?
    }

    private struct UsageIngestBody: Encodable {
        let runId: String?
        let agentId: String?
        let model: String?
        let tokensIn: Int
        let tokensOut: Int
        let cost: Double
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = url(for: path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyAuthHeaders(to: &request)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, body: B, as type: T.Type = T.self) async throws -> T {
        let url = url(for: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)
        applyAuthHeaders(to: &request)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func url(for path: String) -> URL {
        if let queryIndex = path.firstIndex(of: "?") {
            let pathPart = String(path[..<queryIndex]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let query = String(path[path.index(after: queryIndex)...])
            var components = URLComponents(
                url: baseURL.appendingPathComponent(pathPart),
                resolvingAgainstBaseURL: false
            )!
            components.query = query
            return components.url!
        }
        return baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private func applyAuthHeaders(to request: inout URLRequest) {
        if let customerId = auth.customerId, !customerId.isEmpty {
            request.setValue(customerId, forHTTPHeaderField: "X-Customer-Id")
        }
        if let token = auth.appAccountToken, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-App-Account-Token")
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ConduitError.invalidResponse(detail: "non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ConduitError.providerUnavailable(name: "control-plane", status: http.statusCode)
        }
    }

    private func mapAgent(_ backend: BackendAgent) -> HostedAgent {
        Self.mapAgent(backend)
    }

    private func mapRun(_ backend: BackendRun) -> AgentRun {
        Self.mapRun(backend)
    }
}

#if DEBUG
/// In-memory control plane for simulator runs when no backend URL is configured.
public actor DebugHostedAgentStore {
    public static let shared = DebugHostedAgentStore()

    private var agents: [HostedAgent] = []
    private var runs: [String: AgentRun] = [:]

    public init() {}

    public func reset() {
        agents = []
        runs = [:]
    }

    public func listAgents() -> [HostedAgent] { agents }

    public func upsertAgent(_ agent: HostedAgent) {
        if let idx = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[idx] = agent
        } else {
            agents.append(agent)
        }
    }

    public func listRuns(agentID: String) -> [AgentRun] {
        runs.values.filter { $0.agentID == agentID }.sorted { $0.startedAt > $1.startedAt }
    }

    public func upsertRun(_ run: AgentRun) {
        runs[run.id] = run
    }

    public func fetchRun(id: String) -> AgentRun? {
        runs[id]
    }
}
#endif
