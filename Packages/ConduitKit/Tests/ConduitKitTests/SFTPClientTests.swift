import Testing
import Foundation
import CryptoKit
@testable import SSHTransport
@testable import ConduitCore
@testable import SecurityKit

@Suite("SFTPClient")
struct SFTPClientTests {
    // Integration test — requires a real SSH host. Skipped when the env var is absent.
    @Test func listDirectoryRoundTrip() async throws {
        guard let host = ProcessInfo.processInfo.environment["CONDUIT_SSH_HOST"] else {
            return  // skip in CI
        }
        guard
            let user = ProcessInfo.processInfo.environment["CONDUIT_SSH_USER"],
            let rawKey = ProcessInfo.processInfo.environment["CONDUIT_SSH_ED25519_PRIVATE_KEY_B64"],
            let keyData = Data(base64Encoded: rawKey),
            let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
        else {
            return
        }

        let testHost = Host(
            name: "integration",
            hostname: host,
            username: user,
            authMethod: .ed25519(keyID: KeyID())
        )
        let session = SSHSession(host: testHost)
        let hostKeyStore = HostKeyStore(inMemory: true)
        try await session.connect(credential: .ed25519(key), hostKeyStore: hostKeyStore)
        defer { Task { await session.disconnect() } }

        let client = SFTPClient(session: session)
        let root = try await client.list(path: ".")
        #expect(!root.isEmpty)

        let fixtureName = "conduit-sftp-test-\(UUID().uuidString.prefix(8)).txt"
        let fixturePath = "./\(fixtureName)"
        let payload = Data("hello from conduit tests\n".utf8)
        try await client.write(path: fixturePath, data: payload)
        let downloaded = try await client.download(path: fixturePath)
        #expect(downloaded == payload)
        try await client.remove(path: fixturePath)
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

    @Test func parseLsOutputSkipsDotsAndSortsDirectoriesFirst() {
        let output = """
        drwxr-xr-x 2 roshan staff 4096 2026-05-25 10:00 zeta
        -rw-r--r-- 1 roshan staff  220 2026-05-25 10:01 alpha.txt
        drwxr-xr-x 2 roshan staff 4096 2026-05-25 10:00 beta
        drwxr-xr-x 2 roshan staff 4096 2026-05-25 10:00 .
        drwxr-xr-x 2 roshan staff 4096 2026-05-25 10:00 ..
        """
        let entries = SFTPClient.parseLongListing(output, parent: "/tmp")
        #expect(entries.map(\.name) == ["beta", "zeta", "alpha.txt"])
        #expect(entries[0].isDirectory)
        #expect(!entries[2].isDirectory)
    }
}
