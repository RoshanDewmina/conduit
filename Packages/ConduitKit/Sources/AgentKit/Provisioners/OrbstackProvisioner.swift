import Foundation
import ConduitCore

/// Provisions an OrbStack Linux VM on the local machine.
/// OrbStack must be running and its CLI (`orb`) must be installed.
public actor OrbstackProvisioner: Provisioner {
    private let baseURL = URL(string: "http://127.0.0.1:28935")!

    public init() {}

    public func create(plan: ProvisioningPlan, log: @escaping @Sendable (String) async -> Void) async throws -> ConduitCore.Host {
        await log("Creating OrbStack VM '\(plan.name)'...")

        // Check OrbStack is accessible
        let pingURL = baseURL.appendingPathComponent("/api/v1/version")
        guard (try? await URLSession.shared.data(from: pingURL)) != nil else {
            throw ProvisioningError.apiError("OrbStack not running. Start OrbStack and try again.")
        }

        // OrbStack REST API: create a new machine
        let createURL = baseURL.appendingPathComponent("/api/v1/machines")
        var request = URLRequest(url: createURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "name": plan.name,
            "distro": "ubuntu",
            "arch": "aarch64"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ProvisioningError.apiError("Failed to create OrbStack VM")
        }

        await log("OrbStack VM created. Installing packages...")

        // Parse machine info
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let vmName = json["name"] as? String {
            await log("VM '\(vmName)' ready. SSH available at 127.0.0.1.")
        }

        return ConduitCore.Host(
            name: plan.name,
            hostname: "127.0.0.1",
            port: 22,
            username: "root",
            authMethod: .password,
            tags: ["orbstack", "local"]
        )
    }
}
