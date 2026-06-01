#if os(iOS)
import Foundation
import ConduitCore

/// Parsed result from an SSH command string.
/// Extends the WorkspacesView quick-connect parser with `-i <keyfile>` capture.
public struct SSHParseResult: Sendable {
    public let user: String
    public let host: String
    public let port: Int
    public let identityFile: String?   // path from -i flag, if present

    /// Derived display name — "user@host" unless port is non-standard.
    public var displayName: String {
        port == 22 ? "\(user)@\(host)" : "\(user)@\(host):\(port)"
    }
}

/// Parse a free-form SSH command string.
///
/// Accepts:
///   - `user@host`
///   - `ssh user@host`
///   - `ssh user@host -p 2222`
///   - `ssh -p 2222 user@host`
///   - `ssh -i ~/.ssh/id_ed25519 user@host`
///   - Any combination of the above flags (order independent)
///
/// Returns `nil` if the string can't be parsed into a valid user@host.
public func parseSSHCommand(_ text: String) -> SSHParseResult? {
    let t = text.trimmingCharacters(in: .whitespaces)
    guard !t.isEmpty else { return nil }

    // Strip optional leading "ssh" keyword
    var remainder = t
    if remainder.lowercased().hasPrefix("ssh ") {
        remainder = String(remainder.dropFirst(4)).trimmingCharacters(in: .whitespaces)
    } else if remainder.lowercased() == "ssh" {
        return nil
    }

    // Extract flags (-p port, -i keyfile) and the positional user@host argument
    var port: Int = 22
    var identityFile: String?
    var positional: String?

    var tokens = tokenize(remainder)
    var idx = 0
    while idx < tokens.count {
        let tok = tokens[idx]
        if tok == "-p" {
            idx += 1
            if idx < tokens.count, let p = Int(tokens[idx]), (1...65535).contains(p) {
                port = p
            }
        } else if tok.hasPrefix("-p") {
            // e.g. -p2222 (no space)
            let value = String(tok.dropFirst(2))
            if let p = Int(value), (1...65535).contains(p) { port = p }
        } else if tok == "-i" {
            idx += 1
            if idx < tokens.count { identityFile = tokens[idx] }
        } else if tok.hasPrefix("-i") {
            identityFile = String(tok.dropFirst(2))
        } else if tok.hasPrefix("-") {
            // Skip other flags (e.g. -o, -A, -v, etc.) and their potential arg
            // Conservatively skip one following value for flags known to take args.
            let knownArgFlags = ["-o", "-l", "-b", "-c", "-e", "-F", "-m", "-w", "-W"]
            if knownArgFlags.contains(tok) { idx += 1 }
        } else {
            // Treat as positional (user@host or host)
            positional = tok
        }
        idx += 1
    }

    guard let pos = positional else { return nil }

    // Parse user@host
    if let atRange = pos.range(of: "@") {
        let user = String(pos[pos.startIndex..<atRange.lowerBound])
        let host = String(pos[atRange.upperBound...])
        guard !user.isEmpty, !host.isEmpty,
              isValidUser(user), isValidHost(host) else { return nil }

        // Strip optional :port suffix (e.g. admin@192.168.1.1:2222)
        var resolvedHost = host
        var resolvedPort = port
        if let colonIdx = host.lastIndex(of: ":"),
           !host.hasPrefix("["),   // not an IPv6 literal
           let p = Int(host[host.index(after: colonIdx)...]),
           (1...65535).contains(p) {
            resolvedHost = String(host[..<colonIdx])
            resolvedPort = p
        }

        return SSHParseResult(user: user, host: resolvedHost, port: resolvedPort, identityFile: identityFile)
    }

    // No "@" — bare hostname, no user to infer safely
    return nil
}

/// Build a `Host` from a parsed SSH result (no key assigned — caller must set authMethod).
public func host(from parsed: SSHParseResult) -> Host {
    Host(
        id: HostID(),
        name: parsed.displayName,
        hostname: parsed.host,
        port: parsed.port,
        username: parsed.user,
        authMethod: .password,
        tmuxSessionName: nil,
        lastConnectedAt: nil
    )
}

// MARK: - Private helpers

private func tokenize(_ s: String) -> [String] {
    // Simple whitespace tokenizer that respects single/double-quoted strings.
    var tokens: [String] = []
    var current = ""
    var inSingle = false
    var inDouble = false
    for ch in s {
        switch ch {
        case "'":
            inSingle.toggle()
        case "\"":
            inDouble.toggle()
        case " " where !inSingle && !inDouble:
            if !current.isEmpty { tokens.append(current); current = "" }
        case "\t" where !inSingle && !inDouble:
            if !current.isEmpty { tokens.append(current); current = "" }
        default:
            current.append(ch)
        }
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
}

private func isValidUser(_ s: String) -> Bool {
    s.range(of: #"^[a-zA-Z0-9_.\-]+$"#, options: .regularExpression) != nil
}

private func isValidHost(_ s: String) -> Bool {
    s.range(of: #"^[a-zA-Z0-9_.\-\[\]]+$"#, options: .regularExpression) != nil
        && !s.isEmpty
}

#endif
