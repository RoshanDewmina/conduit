import Foundation
import ConduitCore

public struct DaemonManifestAsset: Sendable {
    public let os: String
    public let arch: String
    public let url: String
    public let sha256: String
}

public struct DaemonManifest: Sendable {
    public let version: String
    public let assets: [DaemonManifestAsset]
}

public actor DaemonBootstrap {
    public static let binDir = "~/.conduit/bin"

    // Returns the path to a ready-to-run conduitd binary on the remote host.
    // If already installed at the correct version, returns immediately.
    // Otherwise has the remote host download + verify + install it.
    public static func ensureInstalled(session: SSHSession, manifest: DaemonManifest) async throws -> String {
        // 1. Detect remote OS and arch
        let unameOutput = (try? await session.executeCollected("uname -sm")) ?? ""
        let parts = unameOutput.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        let remoteOS = parts.first.map(String.init)?.lowercased() ?? "linux"
        let rawArch = parts.dropFirst().first.map(String.init)?.lowercased() ?? "amd64"
        let arch = rawArch.contains("arm") || rawArch.contains("aarch") ? "arm64" : "amd64"

        // 2. Find matching asset
        guard let asset = manifest.assets.first(where: { $0.os == remoteOS && $0.arch == arch }) else {
            throw ConduitError.unsupportedPlatform
        }

        let binPath = "\(binDir)/conduitd-\(manifest.version)"

        // 3. Check if already installed and valid
        let checkOutput = (try? await session.executeCollected(
            "test -f \(binPath) && sha256sum \(binPath) 2>/dev/null | awk '{print $1}'"
        )) ?? ""
        if checkOutput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == asset.sha256.lowercased() {
            return binPath  // already installed and verified
        }

        // 4. Install: create dir, download, verify, chmod
        _ = try? await session.executeCollected("mkdir -p \(binDir)")
        _ = try? await session.executeCollected(
            "curl -fsSL '\(asset.url)' -o \(binPath).tmp && mv \(binPath).tmp \(binPath)"
        )
        let actualSHA = (try? await session.executeCollected(
            "sha256sum \(binPath) | awk '{print $1}'"
        ))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard actualSHA.lowercased() == asset.sha256.lowercased() else {
            _ = try? await session.executeCollected("rm -f \(binPath)")
            throw ConduitError.unknown(detail: "conduitd SHA-256 mismatch: got \(actualSHA), expected \(asset.sha256)")
        }
        _ = try? await session.executeCollected("chmod +x \(binPath)")
        return binPath
    }

    private static let releaseBase = "https://github.com/RoshanDewmina/conduit/releases/download/v0.1.0"

    public static func loadManifest() -> DaemonManifest {
        DaemonManifest(
            version: "0.1.0",
            assets: [
                DaemonManifestAsset(
                    os: "linux", arch: "arm64",
                    url: "\(releaseBase)/conduitd-linux-arm64",
                    sha256: "f23e734be4cec4ab00649a8f466e3ec8587e71b90c2cc0f889a7fab301cfb274"
                ),
                DaemonManifestAsset(
                    os: "linux", arch: "amd64",
                    url: "\(releaseBase)/conduitd-linux-amd64",
                    sha256: "60cc93f76e40b58b7da16a4aa0f033faa145ce32e1d597fad9caffd33e39769e"
                ),
                DaemonManifestAsset(
                    os: "darwin", arch: "arm64",
                    url: "\(releaseBase)/conduitd-darwin-arm64",
                    sha256: "188876095a0d4ddeb1bc22ac269b3b64f40fd6a575b43e37e4f9bbeb49876958"
                ),
            ]
        )
    }
}
