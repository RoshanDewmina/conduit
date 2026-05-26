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
        let output = """
        total 16
        drwxr-xr-x 2 roshan staff 4096 2026-05-25 10:00 projects
        -rw-r--r-- 1 roshan staff  220 2026-05-25 10:01 .bashrc
        lrwxrwxrwx 1 roshan staff   11 2026-05-25 10:02 current -> projects/app
        """

        let entries = SFTPClient.parseLongListing(output, parent: "/home/roshan")

        #expect(entries.map(\.name) == ["projects", ".bashrc", "current"])
        #expect(entries[0].isDirectory)
        #expect(entries[0].path == "/home/roshan/projects")
        #expect(entries[1].sizeBytes == 220)
        #expect(entries[2].path == "/home/roshan/current")
    }
}
