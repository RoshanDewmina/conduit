import Foundation
import Testing
@testable import AgentKit

@Suite("M6 cloud execution model")
struct HostedAgentM6Tests {
    @Test("runtime kind isCloud classification")
    func isCloud() {
        #expect(HostedRuntimeKind.sshHost.isCloud == false)
        #expect(HostedRuntimeKind.gcpCloudRun.isCloud)
        #expect(HostedRuntimeKind.fly.isCloud)
        #expect(HostedRuntimeKind.lightsail.isCloud)
    }

    @Test("runtime choice maps to backend kind")
    func choiceToKind() {
        #expect(HostedRuntimeChoice.sshHost.runtimeKind == .sshHost)
        #expect(HostedRuntimeChoice.cloud.runtimeKind == .gcpCloudRun)
    }

    @Test("runtime choice derives from stored kind")
    func choiceFromKind() {
        #expect(HostedRuntimeChoice(runtimeKind: .sshHost) == .sshHost)
        #expect(HostedRuntimeChoice(runtimeKind: .gcpCloudRun) == .cloud)
        #expect(HostedRuntimeChoice(runtimeKind: .fly) == .cloud)
        #expect(HostedRuntimeChoice(runtimeKind: .lightsail) == .cloud)
    }

    @Test("region survives DTO round-trip; missing region decodes to nil (back-compat)")
    func regionMapping() {
        let withRegion = HostedAgentAPIClient.BackendAgent(
            id: "a1", name: "Cloud Bot", runtime: "gcp_cloud_run",
            config: .init(model: "anthropic/claude-sonnet-4", hostID: "", command: "claude", workspacePath: nil, region: "eu-west"),
            createdAt: nil, updatedAt: nil
        )
        #expect(HostedAgentAPIClient.mapAgent(withRegion).region == "eu-west")
        #expect(HostedAgentAPIClient.mapAgent(withRegion).runtimeKind == .gcpCloudRun)

        let noRegion = HostedAgentAPIClient.BackendAgent(
            id: "a2", name: "Host Bot", runtime: "ssh-host",
            config: .init(model: "m", hostID: "h", command: "claude", workspacePath: nil, region: nil),
            createdAt: nil, updatedAt: nil
        )
        #expect(HostedAgentAPIClient.mapAgent(noRegion).region == nil)
    }

    @Test("region decodes as nil when the config key is absent")
    func regionDecodeBackCompat() throws {
        // Legacy payload without a `region` field must still decode.
        let json = #"{"model":"m","hostID":"h","command":"claude"}"#
        let config = try JSONDecoder().decode(
            HostedAgentAPIClient.BackendAgentConfig.self,
            from: Data(json.utf8)
        )
        #expect(config.region == nil)
        #expect(config.workspacePath == nil)
        #expect(config.command == "claude")
    }

    @Test("cloud region catalog is non-empty and default is first")
    func regionCatalog() {
        #expect(!CloudRegion.catalog.isEmpty)
        #expect(CloudRegion.default.slug == CloudRegion.catalog[0].slug)
        #expect(CloudRegion.catalog.allSatisfy { !$0.slug.isEmpty && !$0.displayName.isEmpty })
    }
}
