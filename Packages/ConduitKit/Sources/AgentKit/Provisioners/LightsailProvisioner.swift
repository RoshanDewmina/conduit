#if DEBUG
import Foundation
import CryptoKit
import ConduitCore

/// Provisions an AWS Lightsail instance using the Lightsail REST API with SigV4 signing.
/// No external AWS SDK — only CryptoKit + URLSession.
/// Gated to DEBUG — multi-cloud provisioning is post-launch. Only Fly.io ships in v1.
public actor LightsailProvisioner: Provisioner {
    private let accessKey: String
    private let secretKey: String
    private let region: String

    public init(accessKey: String, secretKey: String, region: String = "us-east-1") {
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.region = region
    }

    public func create(plan: ProvisioningPlan, log: @escaping @Sendable (String) async -> Void) async throws -> ConduitCore.Host {
        let instanceName = "conduit-\(plan.name.lowercased().replacingOccurrences(of: " ", with: "-"))-\(UUID().uuidString.prefix(8))"

        await log("Creating Lightsail instance '\(instanceName)' in \(region)…")
        try await createInstance(name: instanceName, plan: plan)
        await log("Instance created. Waiting for it to be running…")

        let ip = try await waitForRunning(name: instanceName, log: log)
        await log("Instance running at \(ip). Opening port 22…")

        try await openPort22(name: instanceName)
        await log("Lightsail instance ready.")

        return Host(
            name: plan.name,
            hostname: ip,
            port: 22,
            username: "ec2-user",
            authMethod: .password,
            tags: ["lightsail", region],
            tmuxSessionName: plan.name
        )
    }

    // MARK: - Lightsail API

    private func createInstance(name: String, plan: ProvisioningPlan) async throws {
        let body: [String: Any] = [
            "instanceNames": [name],
            "availabilityZone": "\(region)a",
            "blueprintId": "amazon_linux_2023",
            "bundleId": lightsailBundle(plan.size),
            "userData": userDataScript(agentCLI: plan.agentCLI)
        ]
        let response = try await lightsailPost(target: "Lightsail_20161128.CreateInstances", body: body)
        guard let ops = response["operations"] as? [[String: Any]],
              let status = ops.first?["status"] as? String,
              status == "Succeeded" || status == "Started" else {
            throw ProvisioningError.apiError("CreateInstances returned unexpected status")
        }
    }

    /// Polls GetInstanceState until the instance is "running", then returns public IP.
    private func waitForRunning(name: String, log: @escaping @Sendable (String) async -> Void) async throws -> String {
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline {
            let body = ["instanceName": name]
            let response = try await lightsailPost(target: "Lightsail_20161128.GetInstance", body: body)
            if let instance = response["instance"] as? [String: Any],
               let state = (instance["state"] as? [String: Any])?["name"] as? String {
                if state == "running" {
                    guard let networking = instance["networking"] as? [String: Any],
                          let ports = networking["ports"] as? [[String: Any]] else {
                        throw ProvisioningError.apiError("Cannot read networking info")
                    }
                    _ = ports
                    if let ip = instance["publicIpAddress"] as? String {
                        return ip
                    }
                    throw ProvisioningError.apiError("No public IP assigned")
                }
                await log("State: \(state)…")
            }
            try await Task.sleep(for: .seconds(8))
        }
        throw ProvisioningError.timeout("Instance did not reach running state within 5 minutes")
    }

    /// Opens port 22 for inbound TCP traffic.
    private func openPort22(name: String) async throws {
        let body: [String: Any] = [
            "instanceName": name,
            "portInfo": ["fromPort": 22, "toPort": 22, "protocol": "tcp"]
        ]
        _ = try await lightsailPost(target: "Lightsail_20161128.OpenInstancePublicPorts", body: body)
    }

    // MARK: - HTTP + SigV4

    private func lightsailPost(target: String, body: [String: Any]) async throws -> [String: Any] {
        let endpoint = URL(string: "https://lightsail.\(region).amazonaws.com")!
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue(target, forHTTPHeaderField: "X-Amz-Target")
        request.setValue("lightsail.\(region).amazonaws.com", forHTTPHeaderField: "Host")
        try sign(request: &request, bodyData: bodyData, service: "lightsail")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw ProvisioningError.apiError(msg ?? "HTTP \(http.statusCode)")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: - AWS SigV4

    private func sign(request: inout URLRequest, bodyData: Data, service: String) throws {
        let now = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let amzDate = dateFormatter.string(from: now).replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
        let dateStamp = String(amzDate.prefix(8))

        request.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")

        let bodyHash = SHA256.hash(data: bodyData).hexString
        request.setValue(bodyHash, forHTTPHeaderField: "X-Amz-Content-Sha256")

        let host = request.value(forHTTPHeaderField: "Host") ?? ""
        let canonicalHeaders = "content-type:\(request.value(forHTTPHeaderField: "Content-Type") ?? "")\nhost:\(host)\nx-amz-content-sha256:\(bodyHash)\nx-amz-date:\(amzDate)\nx-amz-target:\(request.value(forHTTPHeaderField: "X-Amz-Target") ?? "")\n"
        let signedHeaders = "content-type;host;x-amz-content-sha256;x-amz-date;x-amz-target"

        let canonicalRequest = [
            "POST",
            "/",
            "",
            canonicalHeaders,
            signedHeaders,
            bodyHash
        ].joined(separator: "\n")

        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            SHA256.hash(data: Data(canonicalRequest.utf8)).hexString
        ].joined(separator: "\n")

        let signingKey = deriveSigningKey(secretKey: secretKey, dateStamp: dateStamp, region: region, service: service)
        let signature = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: signingKey).hexString

        request.setValue(
            "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)",
            forHTTPHeaderField: "Authorization"
        )
    }

    private func deriveSigningKey(secretKey: String, dateStamp: String, region: String, service: String) -> SymmetricKey {
        let kDate    = HMAC<SHA256>.authenticationCode(for: Data(dateStamp.utf8), using: SymmetricKey(data: Data(("AWS4" + secretKey).utf8)))
        let kRegion  = HMAC<SHA256>.authenticationCode(for: Data(region.utf8),    using: SymmetricKey(data: Data(kDate)))
        let kService = HMAC<SHA256>.authenticationCode(for: Data(service.utf8),   using: SymmetricKey(data: Data(kRegion)))
        let kSigning = HMAC<SHA256>.authenticationCode(for: Data("aws4_request".utf8), using: SymmetricKey(data: Data(kService)))
        return SymmetricKey(data: Data(kSigning))
    }

    // MARK: - Helpers

    private func lightsailBundle(_ size: ProvisioningPlan.MachineSize) -> String {
        switch size {
        case .shared1x:    return "nano_3_0"
        case .shared2x:    return "small_3_0"
        case .performance: return "medium_3_0"
        }
    }

    private func userDataScript(agentCLI: ProvisioningPlan.AgentCLI) -> String {
        """
        #!/bin/bash
        yum update -y
        yum install -y tmux git curl
        curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
        yum install -y nodejs
        \(agentCLI.installCommand)
        systemctl enable --now sshd
        """
    }
}

// MARK: - Hex helper

private extension ContiguousBytes {
    var hexString: String {
        var result = ""
        withUnsafeBytes { result = $0.map { String(format: "%02x", $0) }.joined() }
        return result
    }
}
#endif // DEBUG
