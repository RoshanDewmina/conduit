import Foundation
import SSHTransport

/// Detects listening TCP ports on the remote host via `ss` or `lsof`.
/// Engine module — no UIKit/SwiftUI imports.
public actor PortDetector {
    private static let wellKnown = [3000, 3001, 4000, 5173, 8000, 8080, 8888]

    private let session: SSHSession

    public init(session: SSHSession) {
        self.session = session
    }

    /// Runs a port-discovery command on the remote host and returns any
    /// ports from the well-known dev list, in priority order.
    public func detect() async throws -> [Int] {
        let command = "ss -tlnp 2>/dev/null || lsof -iTCP -sTCP:LISTEN 2>/dev/null"
        let output: String
        do {
            output = try await session.executeCollected(command)
        } catch {
            return []
        }
        return Self.parsePorts(from: output)
    }

    // MARK: - Parsing (static so tests can call it directly)

    /// Parse `ss -tlnp` and `lsof -iTCP -sTCP:LISTEN` output and return
    /// well-known dev ports found, in priority order.
    public static func parsePorts(from output: String) -> [Int] {
        var found = Set<Int>()
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            // --- ss -tlnp format ---
            // LISTEN 0 128 0.0.0.0:3000 0.0.0.0:* users:(...)
            // Extract `:PORT` that appears between a space/start and a space/end,
            // specifically in column position of the local address field.
            if let port = extractSSPort(from: line) {
                found.insert(port)
            }

            // --- lsof -iTCP -sTCP:LISTEN format ---
            // node 1234 user 20u IPv4 ... TCP *:5173 (LISTEN)
            if let port = extractLSOFPort(from: line) {
                found.insert(port)
            }
        }

        // Return matches in priority order, deduplicated
        return wellKnown.filter { found.contains($0) }
    }

    // MARK: - Private helpers

    /// Extract port from `ss` output: looks for `<address>:<port>` followed by whitespace.
    /// Example: `0.0.0.0:3000` or `[::]:8080`
    private static func extractSSPort(from line: String) -> Int? {
        // `ss` lines start with tcp/LISTEN state; skip header
        let lower = line.lowercased()
        guard lower.contains("listen") || lower.hasPrefix("tcp") else { return nil }

        // Match local address column: "ADDR:PORT  PEER"
        // Scan for `:PORT` followed by whitespace or end
        let pattern = #"[\s\[][\d\:\*\[\]]+:(\d+)\s"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, range: range)
        for match in matches {
            if let r = Range(match.range(at: 1), in: line),
               let port = Int(line[r]),
               wellKnown.contains(port) {
                return port
            }
        }
        return nil
    }

    /// Extract port from `lsof` output: looks for `TCP *:PORT (LISTEN)` or `TCP host:PORT (LISTEN)`.
    private static func extractLSOFPort(from line: String) -> Int? {
        guard line.contains("(LISTEN)") else { return nil }
        // Match `:PORT (LISTEN)` or `:PORT\n`
        let pattern = #":(\d+)\s+\(LISTEN\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        if let match = regex.firstMatch(in: line, range: range),
           let r = Range(match.range(at: 1), in: line),
           let port = Int(line[r]),
           wellKnown.contains(port) {
            return port
        }
        return nil
    }
}
