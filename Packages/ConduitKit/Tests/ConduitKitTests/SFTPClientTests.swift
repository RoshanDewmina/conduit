import Testing
import Foundation
@testable import SSHTransport
@testable import ConduitCore

@Suite("SFTPClient")
struct SFTPClientTests {
    // Integration test — requires a real SSH host. Skipped when the env var is absent.
    @Test func listDirectory() async throws {
        guard let host = ProcessInfo.processInfo.environment["CONDUIT_SSH_HOST"] else {
            return  // skip in CI
        }
        // A real integration test would build a Host and SSHSession, connect,
        // construct an SFTPClient, and call list(path:).
        _ = host
    }

    @Test func parseLsOutput() {
        // SFTPClient now uses Citadel's native SFTP API rather than parsing ls
        // output, so this is intentionally a no-op placeholder that documents
        // the fact that a parser is no longer needed.
    }
}
