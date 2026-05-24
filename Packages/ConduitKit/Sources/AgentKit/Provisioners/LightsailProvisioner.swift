import Foundation
import ConduitCore

/// Provisions an AWS Lightsail instance.
/// Requires AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY.
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
        await log("Creating Lightsail instance '\(plan.name)' in \(plan.region)...")
        // Lightsail API is complex (AWS SigV4 signing required).
        // This implementation is a stub — full SigV4 implementation would be production code.
        throw ProvisioningError.apiError("Lightsail provisioner requires AWS SDK integration. Please provision manually and add the host.")
    }
}
