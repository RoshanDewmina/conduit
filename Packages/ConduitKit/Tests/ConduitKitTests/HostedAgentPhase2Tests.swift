import Foundation
import Testing
@testable import AgentKit

@Suite("Hosted agents Phase 2/3 models")
struct HostedAgentPhase2Tests {
    @Test("Runtime kind maps gcp_cloud_run")
    func gcpRuntimeMapping() {
        #expect(HostedAgentAPIClient.mapRuntimeKind("gcp_cloud_run") == .gcpCloudRun)
        #expect(HostedAgentAPIClient.mapRuntime(.gcpCloudRun) == "gcp_cloud_run")
    }

    @Test("Artifact DTO maps download URL from gcsUri")
    func artifactMapping() {
        let backend = HostedAgentAPIClient.BackendArtifact(
            id: "artifact_1",
            runId: "run_1",
            name: "log.txt",
            contentType: "text/plain",
            sizeBytes: 42,
            storageRef: "runs/run_1/log.txt",
            gcsUri: "https://storage.example.com/log.txt",
            createdAt: "2025-06-02T12:00:00Z"
        )
        let mapped = HostedAgentAPIClient.mapArtifact(backend)
        #expect(mapped.downloadURL?.absoluteString == "https://storage.example.com/log.txt")
    }

    @Test("Schedule DTO maps cron fields")
    func scheduleMapping() {
        let backend = HostedAgentAPIClient.BackendSchedule(
            id: "sched_1",
            agentId: "agent_1",
            cronExpr: "@daily",
            command: "claude",
            enabled: true,
            nextRunAt: "2025-06-03T00:00:00Z",
            lastRunAt: nil
        )
        let mapped = HostedAgentAPIClient.mapSchedule(backend)
        #expect(mapped.cronExpr == "@daily")
        #expect(mapped.enabled)
    }

    @Test("Credit balance remaining label")
    func creditLabel() {
        let bal = CreditBalance(prepaidUSD: 12.5)
        #expect(bal.creditsRemainingLabel == "$12.50")
    }

    @Test("Cloud entitlement exposes team org when orgId set")
    func teamOrgFromEntitlement() {
        let ent = CloudEntitlement(active: true, orgId: "org_acme", orgName: "Acme Eng")
        let org = ent.teamOrg
        #expect(org?.orgId == "org_acme")
        #expect(org?.displayName == "Acme Eng")
    }

    @Test("GCP runtime does not require host id")
    func gcpHostRequirement() {
        #expect(!HostedRuntimeKind.gcpCloudRun.requiresHostID)
        #expect(HostedRuntimeKind.sshHost.requiresHostID)
    }
}
