#if os(iOS) && DEBUG
import Foundation
import LancerCore
import PersistenceKit
import SSHTransport

/// Seeds the local database with realistic sample data for simulator runs.
/// Only runs once — guarded by a UserDefaults flag.
@MainActor
public enum DebugSeeder {
    private static let seededKey = "dev.lancer.debugSeeded"

    /// Demo hosts/approvals/snippets — only when explicitly requested via
    /// `LANCER_SEED_DEMO=1` (or UITest reseed seams). Never runs on a normal
    /// dogfood launch.
    public static func seedIfNeeded(env: AppEnvironment) async {
        guard ProcessInfo.processInfo.environment["LANCER_SEED_DEMO"] == "1" else { return }
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        await seed(env: env)
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    /// Force re-seed (useful from Settings debug menu). Still requires
    /// `LANCER_SEED_DEMO=1` so a stray menu tap cannot pollute production.
    public static func reseed(env: AppEnvironment) async {
        guard ProcessInfo.processInfo.environment["LANCER_SEED_DEMO"] == "1" else { return }
        await seed(env: env)
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    /// Reset to a deterministic approvals state for UI tests. Gated on
    /// `LANCER_UITEST_RESEED=1` in the launch environment so it never runs in a
    /// normal session. Wipes existing approvals (so prior decisions don't linger),
    /// re-seeds the fixed sample set (2 pending + 1 decided), and clears the
    /// app-lock opt-in so the suite always starts unlocked.
    public static func resetForUITestIfRequested(env: AppEnvironment) async {
        guard ProcessInfo.processInfo.environment["LANCER_UITEST_RESEED"] == "1" else { return }
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
        NotificationCenter.default.post(name: .lancerSavedHostsDidChange, object: nil)
        UserDefaults.standard.set(true, forKey: "onboardingSeen")
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    /// Seeds a localhost host pointing at this Mac's sshd for the live-loop E2E
    /// test, gated on `LANCER_DAEMON_E2E=1`. Lets the real production connect
    /// flow reach the resident lancerd over SSH to 127.0.0.1:22. Idempotent.
    public static func seedDaemonE2EHostIfRequested(env: AppEnvironment) async {
        let e = ProcessInfo.processInfo.environment
        guard e["LANCER_DAEMON_E2E"] == "1" else { return }
        let user = e["LANCER_TEST_USER"] ?? "roshansilva"
        let hostname = e["LANCER_TEST_HOST"] ?? "127.0.0.1"
        let port = Int(e["LANCER_TEST_PORT"] ?? "22") ?? 22
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

    /// Pairs to a relay code with no UI interaction, gated on
    /// `LANCER_RELAY_PAIR_CODE` (the 6-digit code printed by `lancerd pair`
    /// on the host). Exists because Simulator HID taps are unreliable on
    /// this iOS build (docs/test-runs/2026-07-02-device-hub-matrix-simulator-pass.md);
    /// routes through the exact same `E2ERelayClient` + `RelayFleetHydration.addMachine`
    /// path `RelayPairingSheet`'s `onPaired` callback uses — no shortcut
    /// around the real E2E handshake. Idempotent no-op when unset.
    public static func autoPairRelayIfRequested(into store: RelayFleetStore) async {
        guard let code = ProcessInfo.processInfo.environment["LANCER_RELAY_PAIR_CODE"],
              code.count == 6 else { return }
        // Already connected — do not mint a second machine ID for the same
        // code (L1 serial 2026-07-19: relaunch with pair code + restore churned
        // two clients and raced firstConnectedMachine).
        if store.firstConnectedMachine != nil { return }
        let client = E2ERelayClient(relayURL: RelaySettings.url(), pairingCode: code)
        client.connect()
        for _ in 0..<100 {
            switch client.pairingState {
            case .paired:
                let record = RelayMachineRecord(id: client.machineID, displayName: "Relay host", pairedAt: .now)
                RelayFleetHydration.addMachine(client: client, record: record, to: store)
                return
            case .pairingFailed, .codeExpired:
                client.disconnect()
                return
            case .unpaired, .waitingForPeer:
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        client.disconnect()
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
            Approval(
                id: ApprovalID(),
                sessionID: session,
                agent: .claudeCode,
                kind: .command,
                command: "DROP DATABASE production",
                patch: nil,
                cwd: "/home/ubuntu/myapp",
                risk: .critical,
                createdAt: Date(timeIntervalSinceNow: -60)
            ),
            Approval(
                id: ApprovalID(),
                sessionID: session,
                agent: .claudeCode,
                kind: .askQuestion,
                patch: nil,
                cwd: "/home/ubuntu/myapp",
                risk: .medium,
                createdAt: Date(timeIntervalSinceNow: -90),
                question: "Which approach should I use to fix the race condition in the worker pool?",
                choices: ["Add a mutex", "Use a channel", "Ask me later"]
            ),
            Approval(
                id: ApprovalID(),
                sessionID: session,
                agent: .claudeCode,
                kind: .command,
                command: "kubectl rollout restart deployment/api",
                patch: nil,
                cwd: "/home/ubuntu/myapp",
                risk: .high,
                createdAt: Date(timeIntervalSinceNow: -600),
                decidedAt: Date(timeIntervalSinceNow: -540),
                decision: .expired
            ),
        ]
        for approval in approvals {
            try? await repo.upsert(approval)
        }
    }

    /// Seeds one rich persisted conversation so every CC-parity chat surface
    /// (aggregated tool chips, thinking rows, per-turn summary, markdown
    /// prose) is reachable OFFLINE — the parity screenshot harness cannot
    /// otherwise exercise them without a live agent turn. Gated on
    /// `LANCER_SEED_TRANSCRIPT=1`; idempotent via the fixed conversation id.
    public static func seedTranscriptIfRequested(env: AppEnvironment) async {
        guard ProcessInfo.processInfo.environment["LANCER_SEED_TRANSCRIPT"] == "1" else { return }
        guard let db = try? AppDatabase.openShared() else { return }
        let repo = ChatConversationRepository(db)
        let convID = "conv-parity-seed"
        if let turns = try? await repo.turns(conversationID: convID), !turns.isEmpty { return }

        let base = Date(timeIntervalSinceNow: -600)
        _ = try? await repo.upsertConversationMirror(
            ChatConversation(
                id: convID,
                title: "Parity seed — fix the flaky test",
                agentID: "claudeCode",
                hostName: "seed-host",
                hostID: nil,
                cwd: "/Users/dev/project"
            ),
            lastHostSeq: 12,
            syncState: .synced
        )
        _ = try? await repo.upsertTurnMirror(
            ChatTurn(
                id: "turn-parity-1",
                conversationID: convID,
                ordinal: 0,
                prompt: "Fix the flaky test in AuthTests and update the docs.",
                runID: "run-parity-1",
                status: .completed,
                assistantText: "",
                createdAt: base,
                completedAt: base.addingTimeInterval(34)
            ),
            vendorSessionID: "seed-session",
            hostSeqStart: 1,
            hostSeqEnd: 12
        )

        func chip(_ seq: Int, _ name: String, _ input: String, at offset: TimeInterval) -> ChatEvent {
            ChatEvent(
                conversationID: convID, seq: seq, turnID: "turn-parity-1",
                runID: "run-parity-1", kind: "tool_call", role: nil, stream: nil,
                text: name,
                payloadJSON: #"{"name":"\#(name)","toolUseId":"tu-\#(seq)","input":\#(input)}"#,
                createdAt: base.addingTimeInterval(offset)
            )
        }
        func result(_ seq: Int, forSeq: Int, _ text: String, at offset: TimeInterval) -> ChatEvent {
            ChatEvent(
                conversationID: convID, seq: seq, turnID: "turn-parity-1",
                runID: "run-parity-1", kind: "tool_result", role: nil, stream: nil,
                text: text,
                payloadJSON: #"{"toolUseId":"tu-\#(forSeq)","isError":false}"#,
                createdAt: base.addingTimeInterval(offset)
            )
        }
        let events: [ChatEvent] = [
            ChatEvent(conversationID: convID, seq: 1, turnID: "turn-parity-1", runID: "run-parity-1",
                      kind: "thinking", role: nil, stream: nil,
                      text: "The failure is timing-dependent — the mock clock isn't injected in the retry path, so the assertion races the debounce. I'll pin the clock and rerun.",
                      payloadJSON: nil, createdAt: base.addingTimeInterval(1)),
            ChatEvent(conversationID: convID, seq: 2, turnID: "turn-parity-1", runID: "run-parity-1",
                      kind: "output", role: "assistant", stream: nil,
                      text: "Looking at the failing test now. **AuthTests.retryBackoff** races a real clock — here's the fix:\n\n```swift\nlet clock = TestClock()\n```\n\nRunning the suite to confirm.",
                      payloadJSON: nil, createdAt: base.addingTimeInterval(2)),
            chip(3, "Bash", #"{"command":"swift test --filter AuthTests"}"#, at: 3),
            result(4, forSeq: 3, "PASS 12/12", at: 8),
            chip(5, "Bash", #"{"command":"git status"}"#, at: 9),
            result(6, forSeq: 5, "clean", at: 10),
            chip(7, "Bash", #"{"command":"git diff --stat"}"#, at: 11),
            result(8, forSeq: 7, "2 files changed", at: 12),
            chip(9, "Bash", #"{"command":"swift build"}"#, at: 13),
            result(10, forSeq: 9, "Build complete!", at: 20),
            chip(11, "Edit", #"{"file_path":"/Users/dev/project/docs/testing.md","added":6,"removed":2}"#, at: 25),
            ChatEvent(conversationID: convID, seq: 12, turnID: "turn-parity-1", runID: "run-parity-1",
                      kind: "output", role: "assistant", stream: nil,
                      text: "Done — the clock is injected, all 12 tests pass, and the docs now describe the deterministic-time pattern.",
                      payloadJSON: nil, createdAt: base.addingTimeInterval(30)),
        ]
        try? await repo.appendEventsMirror(conversationID: convID, events: events)
    }

    /// Seeds a LONG deterministic conversation for perf measurement (thread
    /// open→first paint / scroll-to-latest / live-follow on hundreds of
    /// events). Gated on `LANCER_SEED_TRANSCRIPT_COUNT=<turnCount>` (e.g.
    /// `LANCER_SEED_TRANSCRIPT_COUNT=150` seeds 150 turns × 4 events each =
    /// 600 events). Fixed conversation id `conv-perf-seed-<turnCount>` so
    /// re-running with the same count is a no-op (idempotent, like the
    /// existing `LANCER_SEED_TRANSCRIPT` seam) but a different count seeds a
    /// fresh fixture. There is no such count parameter on
    /// `LANCER_SEED_TRANSCRIPT` (that seam is a single fixed 12-event turn) —
    /// this is the new seam added 2026-07-17 for WP1 perf measurement.
    public static func seedLongTranscriptIfRequested(env: AppEnvironment) async {
        guard let raw = ProcessInfo.processInfo.environment["LANCER_SEED_TRANSCRIPT_COUNT"],
              let turnCount = Int(raw), turnCount > 0
        else { return }
        guard let db = try? AppDatabase.openShared() else { return }
        let repo = ChatConversationRepository(db)
        let convID = "conv-perf-seed-\(turnCount)"
        if let turns = try? await repo.turns(conversationID: convID), !turns.isEmpty { return }

        let base = Date(timeIntervalSinceNow: -Double(turnCount) * 60)
        _ = try? await repo.upsertConversationMirror(
            ChatConversation(
                id: convID,
                title: "Perf seed — \(turnCount) turns",
                agentID: "claudeCode",
                hostName: "seed-host",
                hostID: nil,
                cwd: "/Users/dev/project"
            ),
            lastHostSeq: turnCount * 4,
            syncState: .synced
        )

        var seq = 0
        for i in 0..<turnCount {
            let turnID = "turn-perf-\(i)"
            let runID = "run-perf-\(i)"
            let turnStart = base.addingTimeInterval(Double(i) * 45)
            _ = try? await repo.upsertTurnMirror(
                ChatTurn(
                    id: turnID,
                    conversationID: convID,
                    ordinal: i,
                    prompt: "Perf seed turn \(i) — make a small change and verify.",
                    runID: runID,
                    status: .completed,
                    assistantText: "",
                    createdAt: turnStart,
                    completedAt: turnStart.addingTimeInterval(20)
                ),
                vendorSessionID: "seed-session-\(i)",
                hostSeqStart: seq + 1,
                hostSeqEnd: seq + 4
            )

            seq += 1
            let thinking = ChatEvent(
                conversationID: convID, seq: seq, turnID: turnID, runID: runID,
                kind: "thinking", role: nil, stream: nil,
                text: "Working through step \(i) of the perf fixture.",
                payloadJSON: nil, createdAt: turnStart.addingTimeInterval(1)
            )
            seq += 1
            let toolCall = ChatEvent(
                conversationID: convID, seq: seq, turnID: turnID, runID: runID,
                kind: "tool_call", role: nil, stream: nil,
                text: "Bash",
                payloadJSON: #"{"name":"Bash","toolUseId":"tu-\#(seq)","input":{"command":"echo step-\#(i)"}}"#,
                createdAt: turnStart.addingTimeInterval(2)
            )
            seq += 1
            let toolResult = ChatEvent(
                conversationID: convID, seq: seq, turnID: turnID, runID: runID,
                kind: "tool_result", role: nil, stream: nil,
                text: "step-\(i)",
                payloadJSON: #"{"toolUseId":"tu-\#(seq - 1)","isError":false}"#,
                createdAt: turnStart.addingTimeInterval(4)
            )
            seq += 1
            let output = ChatEvent(
                conversationID: convID, seq: seq, turnID: turnID, runID: runID,
                kind: "output", role: "assistant", stream: nil,
                text: "Step \(i) complete — echoed the marker and verified it landed.",
                payloadJSON: nil, createdAt: turnStart.addingTimeInterval(5)
            )
            try? await repo.appendEventsMirror(
                conversationID: convID,
                events: [thinking, toolCall, toolResult, output]
            )
        }
    }
}
#endif // os(iOS) && DEBUG
