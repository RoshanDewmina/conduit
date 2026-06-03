import Foundation
import Testing
@testable import AgentKit

@Suite("M4 ssh-host files / artifact upload")
struct HostedAgentM4Tests {
    @Test("inferContentType maps common extensions")
    func contentTypeKnown() {
        #expect(HostedAgentAPIClient.inferContentType(for: "run.log") == "text/plain")
        #expect(HostedAgentAPIClient.inferContentType(for: "report.json") == "application/json")
        #expect(HostedAgentAPIClient.inferContentType(for: "diff.patch.md") == "text/markdown")
        #expect(HostedAgentAPIClient.inferContentType(for: "archive.tar.gz") == "application/gzip")
        #expect(HostedAgentAPIClient.inferContentType(for: "shot.PNG") == "image/png")
    }

    @Test("inferContentType returns nil for unknown/extensionless names")
    func contentTypeUnknown() {
        #expect(HostedAgentAPIClient.inferContentType(for: "Makefile") == nil)
        #expect(HostedAgentAPIClient.inferContentType(for: "binary.xyz") == nil)
        #expect(HostedAgentAPIClient.inferContentType(for: "noext") == nil)
    }
}
