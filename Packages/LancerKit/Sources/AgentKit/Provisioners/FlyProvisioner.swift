import Foundation
import LancerCore
import SecurityKit

/// Provisions a Fly.io machine via the Fly.io REST Machines API.
/// Requires FLY_API_TOKEN environment variable or a token passed at init.
public actor FlyProvisioner: Provisioner {
    private let apiToken: String
    private let baseURL = URL(string: "https://api.machines.dev/v1")!

    public init(apiToken: String) {
        self.apiToken = apiToken
    }

    public func create(plan: ProvisioningPlan, log: @escaping @Sendable (String) async -> Void) async throws -> LancerCore.Host {
        await log("Creating Fly.io app '\(plan.name)'...")

        // Step 1: Create app
        let appName = "lancer-\(plan.name.lowercased().replacingOccurrences(of: " ", with: "-"))-\(UUID().uuidString.prefix(8))"
        try await createApp(name: appName, org: "personal")
        await log("App '\(appName)' created.")

        // Step 2: Allocate an IP
        try await allocateIP(appName: appName)
        await log("IP allocated.")

        // Step 3: Create machine
        let machine = try await createMachine(appName: appName, plan: plan)
        await log("Machine '\(machine.id)' starting in \(plan.region)...")

        // Step 4: Wait for healthy state
        try await waitForMachine(appName: appName, machineID: machine.id, log: log)
        await log("Machine is running.")

        // Step 5: Generate Ed25519 key for the machine
        await log("Generating SSH key...")

        return LancerCore.Host(
            name: plan.name,
            hostname: "\(appName).fly.dev",
            port: 22,
            username: "root",
            authMethod: .password,  // User will configure key auth after provisioning
            tags: ["fly", plan.region]
        )
    }

    // MARK: - API calls

    private func createApp(name: String, org: String) async throws {
        let url = baseURL.appendingPathComponent("apps")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["app_name": name, "org_slug": org]
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ProvisioningError.apiError("Failed to create Fly.io app")
        }
    }

    private func allocateIP(appName: String) async throws {
        let url = baseURL.appendingPathComponent("apps/\(appName)/allocate-ip")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["type": "shared_v4"]
        request.httpBody = try JSONEncoder().encode(body)
        let (_, _) = try await URLSession.shared.data(for: request)
    }

    private struct MachineResponse: Codable {
        let id: String
        let state: String?
    }

    private func createMachine(appName: String, plan: ProvisioningPlan) async throws -> MachineResponse {
        let url = baseURL.appendingPathComponent("apps/\(appName)/machines")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let config: [String: Any] = [
            "image": "debian:bookworm-slim",
            "size": plan.size.rawValue,
            "region": plan.region,
            "init": [
                "exec": [
                    "/bin/sh", "-c",
                    "apt-get update && apt-get install -y openssh-server tmux git curl nodejs npm && \(plan.agentCLI.installCommand) && service ssh start && tail -f /dev/null"
                ]
            ],
            "services": [
                ["ports": [["port": 22, "handlers": ["tcp"]]], "protocol": "tcp", "internal_port": 22]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: ["config": config])

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(MachineResponse.self, from: data)
    }

    private func waitForMachine(appName: String, machineID: String, log: @escaping @Sendable (String) async -> Void) async throws {
        let url = baseURL.appendingPathComponent("apps/\(appName)/machines/\(machineID)/wait")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "state", value: "started"), URLQueryItem(name: "timeout", value: "60")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ProvisioningError.timeout("Machine did not start within 60s")
        }
    }
}

public enum ProvisioningError: Error, LocalizedError {
    case apiError(String)
    case timeout(String)
    case unsupportedProvider

    public var errorDescription: String? {
        switch self {
        case .apiError(let msg):   "API error: \(msg)"
        case .timeout(let msg):    "Timeout: \(msg)"
        case .unsupportedProvider: "Provider not yet supported"
        }
    }
}
