#if os(iOS) && DEBUG
import Foundation
import ConduitCore
import PersistenceKit

/// Seeds the local database with realistic sample data for simulator runs.
/// Only runs once — guarded by a UserDefaults flag.
@MainActor
public enum DebugSeeder {
    private static let seededKey = "dev.conduit.debugSeeded"

    public static func seedIfNeeded(env: AppEnvironment) async {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        await seed(env: env)
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    /// Force re-seed (useful from Settings debug menu).
    public static func reseed(env: AppEnvironment) async {
        await seed(env: env)
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    /// Reset to a deterministic approvals state for UI tests. Gated on
    /// `CONDUIT_UITEST_RESEED=1` in the launch environment so it never runs in a
    /// normal session. Wipes existing approvals (so prior decisions don't linger),
    /// re-seeds the fixed sample set (2 pending + 1 decided), and clears the
    /// app-lock opt-in so the suite always starts unlocked.
    public static func resetForUITestIfRequested(env: AppEnvironment) async {
        guard ProcessInfo.processInfo.environment["CONDUIT_UITEST_RESEED"] == "1" else { return }
        try? await env.approvalRepo.deleteAll()
        await seedApprovals(env.approvalRepo)
        // Deterministic Fleet "Saved hosts" set for tests/screenshots. Wipe any
        // leftover hosts first (e.g. a stale localhost E2E host from a prior
        // session would otherwise block seeding and break the 'Dev VPS' assertion),
        // then seed. seedHosts mints fresh HostIDs, so clearing first avoids dupes.
        for host in (try? await env.hostRepo.all()) ?? [] {
            try? await env.hostRepo.delete(id: host.id)
        }
        await seedHosts(env.hostRepo)
        UserDefaults.standard.removeObject(forKey: "appLockEnabled")
        UserDefaults.standard.set(true, forKey: "onboardingSeen")
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    /// Seeds a localhost host pointing at this Mac's sshd for the live-loop E2E
    /// test, gated on `CONDUIT_DAEMON_E2E=1`. Lets the real production connect
    /// flow reach the resident conduitd over SSH to 127.0.0.1:22. Idempotent.
    public static func seedDaemonE2EHostIfRequested(env: AppEnvironment) async {
        let e = ProcessInfo.processInfo.environment
        guard e["CONDUIT_DAEMON_E2E"] == "1" else { return }
        let user = e["CONDUIT_TEST_USER"] ?? "roshansilva"
        let hostname = e["CONDUIT_TEST_HOST"] ?? "127.0.0.1"
        let port = Int(e["CONDUIT_TEST_PORT"] ?? "22") ?? 22
        let existing = (try? await env.hostRepo.all()) ?? []
        UserDefaults.standard.set(true, forKey: "onboardingSeen")
        guard !existing.contains(where: {
            $0.hostname == hostname && $0.port == port && $0.username == user
        }) else { return }
        let host = Host(
            name: "This Mac (e2e)",
            hostname: hostname,
            port: port,
            username: user,
            authMethod: .password,
            tags: ["local", "e2e"]
        )
        try? await env.hostRepo.upsert(host)
    }

    private static func seed(env: AppEnvironment) async {
        await seedHosts(env.hostRepo)
        await seedSnippets(env.snippetRepo)
        await seedApprovals(env.approvalRepo)
    }

    private static func seedHosts(_ repo: HostRepository) async {
        let hosts: [Host] = [
            Host(
                name: "Dev VPS",
                hostname: "dev.example.com",
                port: 22,
                username: "ubuntu",
                authMethod: .password,
                tags: ["work", "linux"],
                tmuxSessionName: "main",
                createdAt: Date(timeIntervalSinceNow: -86400 * 30),
                lastConnectedAt: Date(timeIntervalSinceNow: -3600)
            ),
            Host(
                name: "Staging",
                hostname: "staging.example.com",
                port: 22,
                username: "deploy",
                authMethod: .password,
                tags: ["work", "staging"],
                createdAt: Date(timeIntervalSinceNow: -86400 * 14),
                lastConnectedAt: Date(timeIntervalSinceNow: -86400 * 2)
            ),
            Host(
                name: "Raspberry Pi",
                hostname: "192.168.1.42",
                port: 22,
                username: "pi",
                authMethod: .password,
                tags: ["home", "iot"],
                createdAt: Date(timeIntervalSinceNow: -86400 * 60),
                lastConnectedAt: Date(timeIntervalSinceNow: -86400 * 7)
            ),
            Host(
                name: "OrbStack Linux",
                hostname: "127.0.0.1",
                port: 2222,
                username: "user",
                authMethod: .password,
                tags: ["local"],
                createdAt: Date(timeIntervalSinceNow: -86400 * 5),
                lastConnectedAt: Date(timeIntervalSinceNow: -1800)
            ),
        ]
        for host in hosts {
            try? await repo.upsert(host)
        }
    }

    private static func seedSnippets(_ repo: SnippetRepository) async {
        let snippets: [Snippet] = [
            Snippet(
                name: "Git status",
                body: "git status",
                tags: ["git"],
                createdAt: Date(timeIntervalSinceNow: -86400 * 20)
            ),
            Snippet(
                name: "Git log (pretty)",
                body: "git log --oneline --graph --decorate -20",
                tags: ["git"],
                createdAt: Date(timeIntervalSinceNow: -86400 * 20)
            ),
            Snippet(
                name: "Docker ps",
                body: "docker ps --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}'",
                tags: ["docker"],
                createdAt: Date(timeIntervalSinceNow: -86400 * 15)
            ),
            Snippet(
                name: "Tail app logs",
                body: "journalctl -u app.service -f --no-pager",
                tags: ["logs", "systemd"],
                createdAt: Date(timeIntervalSinceNow: -86400 * 10)
            ),
            Snippet(
                name: "CPU / memory",
                body: "top -b -n1 | head -20",
                tags: ["monitoring"],
                createdAt: Date(timeIntervalSinceNow: -86400 * 8)
            ),
            Snippet(
                name: "List listening ports",
                body: "ss -tlnp",
                tags: ["network"],
                createdAt: Date(timeIntervalSinceNow: -86400 * 6)
            ),
            Snippet(
                name: "Disk usage",
                body: "df -h && du -sh /* 2>/dev/null | sort -h | tail -20",
                tags: ["disk"],
                createdAt: Date(timeIntervalSinceNow: -86400 * 4)
            ),
            Snippet(
                name: "NPM dev server",
                body: "npm run dev -- --host 0.0.0.0",
                tags: ["node", "dev"],
                createdAt: Date(timeIntervalSinceNow: -86400 * 3)
            ),
        ]
        for snippet in snippets {
            try? await repo.upsert(snippet)
        }
    }
    public static func makeDebugApprovals() -> [Approval] {
        let session = SessionID()
        return [
            Approval(
                id: ApprovalID(),
                sessionID: session,
                agent: .claudeCode,
                kind: .command,
                command: "rm -rf ./dist && npm run build:prod",
                patch: nil,
                cwd: "/home/ubuntu/myapp",
                risk: .high,
                createdAt: Date(timeIntervalSinceNow: -30)
            ),
            Approval(
                id: ApprovalID(),
                sessionID: session,
                agent: .claudeCode,
                kind: .command,
                command: "git push origin main --force-with-lease",
                patch: nil,
                cwd: "/home/ubuntu/myapp",
                risk: .medium,
                createdAt: Date(timeIntervalSinceNow: -120)
            ),
            Approval(
                id: ApprovalID(),
                sessionID: session,
                agent: .claudeCode,
                kind: .command,
                command: "systemctl restart app.service",
                patch: nil,
                cwd: "/home/ubuntu/myapp",
                risk: .low,
                createdAt: Date(timeIntervalSinceNow: -300),
                decidedAt: Date(timeIntervalSinceNow: -295),
                decision: .approved
            ),
        ]
    }

    private static func seedApprovals(_ repo: ApprovalRepository) async {
        let session = SessionID()
        let approvals: [Approval] = [
            Approval(
                id: ApprovalID(),
                sessionID: session,
                agent: .claudeCode,
                kind: .command,
                command: "rm -rf ./dist && npm run build:prod",
                patch: nil,
                cwd: "/home/ubuntu/myapp",
                risk: .high,
                createdAt: Date(timeIntervalSinceNow: -30)
            ),
            Approval(
                id: ApprovalID(),
                sessionID: session,
                agent: .claudeCode,
                kind: .command,
                command: "git push origin main --force-with-lease",
                patch: nil,
                cwd: "/home/ubuntu/myapp",
                risk: .medium,
                createdAt: Date(timeIntervalSinceNow: -120)
            ),
            Approval(
                id: ApprovalID(),
                sessionID: session,
                agent: .claudeCode,
                kind: .command,
                command: "systemctl restart app.service",
                patch: nil,
                cwd: "/home/ubuntu/myapp",
                risk: .low,
                createdAt: Date(timeIntervalSinceNow: -300),
                decidedAt: Date(timeIntervalSinceNow: -295),
                decision: .approved
            ),
        ]
        for approval in approvals {
            try? await repo.upsert(approval)
        }
    }
}
#endif // os(iOS) && DEBUG
