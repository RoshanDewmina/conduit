import Foundation
import LancerCore

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
    /// Raised by workspace git operations when the agent has no workspacePath set.
    case workspaceNotConfigured
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
    public var clientToken: String?

    public init(customerId: String? = nil, appAccountToken: String? = nil, clientToken: String? = nil) {
        self.customerId = customerId
        self.appAccountToken = appAccountToken
        self.clientToken = clientToken
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
            config: .init(
                model: agent.model,
                hostID: agent.hostID ?? "",
                command: agent.command ?? "",
                workspacePath: agent.workspacePath,
                region: agent.region
            )
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

    // MARK: Credits

    public func fetchCredits() async throws -> CreditBalance {
        try await get("billing/credits")
    }

    /// Optional server quota endpoint; returns nil on 404.
    public func fetchQuota() async -> HostedQuotaSnapshot? {
        do {
            return try await get("billing/quota")
        } catch let error as LancerError {
            if case .providerUnavailable(_, let status) = error, status == 404 {
                return nil
            }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: Artifacts

    public func listArtifacts(runID: String) async throws -> [AgentArtifact] {
        let response: ArtifactsListResponse = try await get("runs/\(runID)/artifacts")
        return response.artifacts.map(Self.mapArtifact)
    }

    /// POST /runs/{id}/artifacts — registers artifact metadata (bytes are stored
    /// out-of-band: on the ssh-host via SFTP, or in GCS for cloud runs).
    public func createArtifact(
        runID: String,
        name: String,
        storageRef: String,
        contentType: String? = nil,
        sizeBytes: Int64? = nil
    ) async throws -> AgentArtifact {
        let body = CreateArtifactBody(
            name: name,
            storageRef: storageRef,
            contentType: contentType,
            sizeBytes: sizeBytes
        )
        let created: BackendArtifact = try await post("runs/\(runID)/artifacts", body: body)
        return Self.mapArtifact(created)
    }

    /// DELETE /runs/{id}/artifacts/{artifactId}.
    public func deleteArtifact(runID: String, artifactID: String) async throws {
        try await delete("runs/\(runID)/artifacts/\(artifactID)")
    }

    /// GET /runs/{id}/artifacts/{artifactId}/download — returns a short-lived
    /// signed download URL for cloud (GCS-backed) artifacts. ssh-host artifacts
    /// have no signed URL; use SFTP instead.
    public func artifactDownloadURL(runID: String, artifactID: String) async throws -> URL {
        let response: ArtifactDownloadResponse = try await get("runs/\(runID)/artifacts/\(artifactID)/download")
        guard let url = URL(string: response.url) else {
            throw LancerError.invalidResponse(detail: "artifact download endpoint returned an invalid URL")
        }
        return url
    }

    // MARK: Run logs / control

    /// GET /runs/{id}/logs?since=N — incremental tail of a run's output.
    public func fetchRunLogs(runID: String, since: Int) async throws -> RunLogsPage {
        let response: RunLogsResponse = try await get("runs/\(runID)/logs?since=\(since)")
        return RunLogsPage(
            lines: response.lines.map(Self.mapLogLine),
            nextSince: response.nextSince
        )
    }

    /// POST /runs/{id}/cancel — sets the cancel flag; cloud runners honor it.
    public func requestCancel(runID: String) async throws {
        let _: OKResponse = try await post("runs/\(runID)/cancel", body: EmptyBody())
    }

    // MARK: Schedules

    public func listSchedules(agentID: String) async throws -> [AgentSchedule] {
        let response: SchedulesListResponse = try await get("agents/\(agentID)/schedules")
        return response.schedules.map(Self.mapSchedule)
    }

    public func createSchedule(agentID: String, cronExpr: String, command: String?, enabled: Bool = true) async throws -> AgentSchedule {
        let body = CreateScheduleBody(cronExpr: cronExpr, command: command, enabled: enabled)
        let created: BackendSchedule = try await post("agents/\(agentID)/schedules", body: body)
        return Self.mapSchedule(created)
    }

    /// POST /schedules/{id}/trigger — manual "run now"; returns the created run.
    public func triggerSchedule(scheduleID: String) async throws -> AgentRun {
        let response: TriggerScheduleResponse = try await post(
            "schedules/\(scheduleID)/trigger",
            body: EmptyBody()
        )
        return Self.mapRun(response.run)
    }

    /// PATCH /schedules/{id} — only non-nil fields are applied server-side.
    public func updateSchedule(
        scheduleID: String,
        cronExpr: String? = nil,
        command: String? = nil,
        enabled: Bool? = nil
    ) async throws -> AgentSchedule {
        let body = UpdateScheduleBody(cronExpr: cronExpr, command: command, enabled: enabled)
        let updated: BackendSchedule = try await patch("schedules/\(scheduleID)", body: body)
        return Self.mapSchedule(updated)
    }

    /// DELETE /schedules/{id} — 204 No Content on success.
    public func deleteSchedule(scheduleID: String) async throws {
        try await delete("schedules/\(scheduleID)")
    }

    // MARK: Orgs

    public func listOrgMembers(orgID: String) async throws -> [OrgMember] {
        let response: OrgMembersListResponse = try await get("orgs/\(orgID)/members")
        return response.members.map(Self.mapOrgMember)
    }

    public func inviteOrgMember(orgID: String, email: String, role: String?) async throws -> OrgMember {
        let body = InviteMemberBody(email: email, role: role)
        let created: BackendOrgMember = try await post("orgs/\(orgID)/members", body: body)
        return Self.mapOrgMember(created)
    }

    // MARK: Billing portal

    /// POST /billing/portal — returns a Stripe customer-portal URL. No bearer auth required.
    public func billingPortalURL(customerId: String, returnURL: String?) async throws -> URL {
        let body = PortalBody(customerId: customerId, returnURL: returnURL)
        let response: PortalResponse = try await post("billing/portal", body: body)
        guard let url = URL(string: response.url) else {
            throw LancerError.invalidResponse(detail: "billing portal returned an invalid URL")
        }
        return url
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
            workspacePath: backend.config?.workspacePath,
            region: backend.config?.region,
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
            endedAt: parseRFC3339(backend.completedAt),
            exitCode: backend.exitCode
        )
    }

    static func mapRuntimeKind(_ runtime: String) -> HostedRuntimeKind {
        switch runtime {
        case "fly": .fly
        case "gcp_cloud_run", "gcp-cloud-run": .gcpCloudRun
        case "lightsail": .lightsail
        default: .sshHost
        }
    }

    static func mapRuntime(_ kind: HostedRuntimeKind) -> String {
        switch kind {
        case .sshHost: "ssh-host"
        case .fly: "fly"
        case .gcpCloudRun: "gcp_cloud_run"
        case .lightsail: "lightsail"
        }
    }

    static func mapArtifact(_ backend: BackendArtifact) -> AgentArtifact {
        AgentArtifact(
            id: backend.id,
            runID: backend.runId,
            name: backend.name,
            contentType: backend.contentType,
            sizeBytes: backend.sizeBytes,
            storageRef: backend.storageRef,
            gcsURI: backend.gcsUri,
            createdAt: parseRFC3339(backend.createdAt)
        )
    }

    /// Best-effort MIME type from a filename extension; nil when unknown so the
    /// backend can fall back to `application/octet-stream`. Used when registering
    /// ssh-host artifacts whose bytes live on the remote host.
    public static func inferContentType(for filename: String) -> String? {
        let ext = (filename as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        switch ext {
        case "txt", "log":  return "text/plain"
        case "json":        return "application/json"
        case "md":          return "text/markdown"
        case "csv":         return "text/csv"
        case "html", "htm": return "text/html"
        case "xml":         return "application/xml"
        case "yaml", "yml": return "application/yaml"
        case "pdf":         return "application/pdf"
        case "zip":         return "application/zip"
        case "tar":         return "application/x-tar"
        case "gz", "tgz":   return "application/gzip"
        case "png":         return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":         return "image/gif"
        case "svg":         return "image/svg+xml"
        default:            return nil
        }
    }

    static func mapSchedule(_ backend: BackendSchedule) -> AgentSchedule {
        AgentSchedule(
            id: backend.id,
            agentID: backend.agentId,
            cronExpr: backend.cronExpr,
            command: backend.command,
            enabled: backend.enabled,
            nextRunAt: parseRFC3339(backend.nextRunAt),
            lastRunAt: parseRFC3339(backend.lastRunAt)
        )
    }

    static func mapLogLine(_ backend: BackendLogLine) -> RunLogLine {
        RunLogLine(
            id: "log_\(backend.seq)",
            timestamp: parseRFC3339(backend.ts) ?? .now,
            text: backend.text
        )
    }

    static func mapOrgMember(_ backend: BackendOrgMember) -> OrgMember {
        OrgMember(
            id: backend.id,
            orgId: backend.orgId,
            email: backend.email,
            role: backend.role ?? "member",
            invitedAt: parseRFC3339(backend.invitedAt),
            status: backend.status ?? "invited"
        )
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
        let workspacePath: String?
        let region: String?
    }

    struct BackendRun: Decodable, Equatable {
        let id: String
        let agentId: String
        let status: String
        let command: String?
        let startedAt: String?
        let completedAt: String?
        let createdAt: String?
        let exitCode: Int?
    }

    private struct CreateAgentBody: Encodable {
        let name: String
        let runtime: String
        let config: Config

        struct Config: Encodable {
            let model: String
            let hostID: String
            let command: String
            let workspacePath: String?
            let region: String?
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

    private struct ArtifactsListResponse: Decodable { let artifacts: [BackendArtifact] }

    private struct CreateArtifactBody: Encodable {
        let name: String
        let storageRef: String
        let contentType: String?
        let sizeBytes: Int64?
    }
    private struct SchedulesListResponse: Decodable { let schedules: [BackendSchedule] }

    struct BackendArtifact: Decodable, Equatable {
        let id: String
        let runId: String
        let name: String
        let contentType: String?
        let sizeBytes: Int64?
        let storageRef: String
        let gcsUri: String?
        let createdAt: String?
    }

    struct BackendSchedule: Decodable, Equatable {
        let id: String
        let agentId: String
        let cronExpr: String
        let command: String?
        let enabled: Bool
        let nextRunAt: String?
        let lastRunAt: String?
    }

    private struct CreateScheduleBody: Encodable {
        let cronExpr: String
        let command: String?
        let enabled: Bool
    }

    /// Optional members; synthesized `encodeIfPresent` omits nil so the PATCH
    /// only carries fields the caller actually wants to change.
    private struct UpdateScheduleBody: Encodable {
        let cronExpr: String?
        let command: String?
        let enabled: Bool?
    }

    private struct EmptyBody: Encodable {}

    private struct OKResponse: Decodable { let ok: Bool? }

    private struct ArtifactDownloadResponse: Decodable { let url: String }

    private struct RunLogsResponse: Decodable {
        let lines: [BackendLogLine]
        let nextSince: Int
    }

    struct BackendLogLine: Decodable, Equatable {
        let seq: Int
        let stream: String?
        let text: String
        let ts: String?
    }

    private struct TriggerScheduleResponse: Decodable {
        let run: BackendRun
    }

    private struct OrgMembersListResponse: Decodable { let members: [BackendOrgMember] }

    struct BackendOrgMember: Decodable, Equatable {
        let id: String
        let orgId: String
        let email: String
        let role: String?
        let invitedAt: String?
        let status: String?
    }

    private struct InviteMemberBody: Encodable {
        let email: String
        let role: String?
    }

    private struct PortalBody: Encodable {
        let customerId: String
        let returnURL: String?
    }

    private struct PortalResponse: Decodable {
        let url: String
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

    private func patch<B: Encodable, T: Decodable>(_ path: String, body: B, as type: T.Type = T.self) async throws -> T {
        let url = url(for: path)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)
        applyAuthHeaders(to: &request)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    /// DELETE with no response body (expects 2xx, typically 204).
    private func delete(_ path: String) async throws {
        let url = url(for: path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        applyAuthHeaders(to: &request)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
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
        if let clientToken = auth.clientToken, !clientToken.isEmpty {
            request.setValue("Bearer \(clientToken)", forHTTPHeaderField: "Authorization")
        }
        if let customerId = auth.customerId, !customerId.isEmpty {
            request.setValue(customerId, forHTTPHeaderField: "X-Customer-Id")
        }
        if let token = auth.appAccountToken, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-App-Account-Token")
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LancerError.invalidResponse(detail: "non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LancerError.providerUnavailable(name: "control-plane", status: http.statusCode)
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
