import Foundation
import GRDB
import LancerCore

public actor LoopRepository {
    private let db: AppDatabase
    public init(_ db: AppDatabase) { self.db = db }

    public func upsert(_ loop: Loop) async throws {
        let filesJSON = (try? String(data: JSONEncoder().encode(loop.filesChanged), encoding: .utf8)) ?? "[]"
        let cmdsJSON = (try? String(data: JSONEncoder().encode(loop.commandsRun), encoding: .utf8)) ?? "[]"
        let testsJSON = (try? String(data: JSONEncoder().encode(loop.testsRun), encoding: .utf8)) ?? "[]"
        let proofJSON = loop.proof.flatMap { (try? String(data: JSONEncoder().encode($0), encoding: .utf8)) }

        try await db.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO loops (
                    id, goal, plan, current_step, blocked_reason,
                    agent, vendor, model, host_id, repo, branch, worktree,
                    files_changed, commands_run, tests_run,
                    approvals_asked, approvals_decided, policy_exceptions,
                    spend_usd, input_tokens, output_tokens,
                    status, started_at, completed_at, last_activity_at,
                    proof, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    goal=excluded.goal, plan=excluded.plan,
                    current_step=excluded.current_step, blocked_reason=excluded.blocked_reason,
                    agent=excluded.agent, vendor=excluded.vendor, model=excluded.model,
                    host_id=excluded.host_id, repo=excluded.repo, branch=excluded.branch,
                    worktree=excluded.worktree,
                    files_changed=excluded.files_changed, commands_run=excluded.commands_run,
                    tests_run=excluded.tests_run,
                    approvals_asked=excluded.approvals_asked,
                    approvals_decided=excluded.approvals_decided,
                    policy_exceptions=excluded.policy_exceptions,
                    spend_usd=excluded.spend_usd,
                    input_tokens=excluded.input_tokens, output_tokens=excluded.output_tokens,
                    status=excluded.status, started_at=excluded.started_at,
                    completed_at=excluded.completed_at,
                    last_activity_at=excluded.last_activity_at,
                    proof=excluded.proof, updated_at=CURRENT_TIMESTAMP
            """, arguments: [
                loop.id,
                loop.goal,
                loop.plan,
                loop.currentStep,
                loop.blockedReason.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) },
                loop.agent,
                loop.vendor,
                loop.model,
                loop.hostID,
                loop.repo,
                loop.branch,
                loop.worktree,
                filesJSON,
                cmdsJSON,
                testsJSON,
                loop.approvalsAsked,
                loop.approvalsDecided,
                loop.policyExceptions,
                loop.spendUSD,
                loop.tokenCount?.inputTokens ?? 0,
                loop.tokenCount?.outputTokens ?? 0,
                loop.status.rawValue,
                loop.startedAt,
                loop.completedAt,
                loop.lastActivityAt,
                proofJSON,
                loop.startedAt,
            ])
        }
    }

    public func byID(_ id: String) async throws -> Loop? {
        try await db.dbWriter.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM loops WHERE id = ?", arguments: [id]) else {
                return nil
            }
            return Self.decode(row)
        }
    }

    public func activeLoops() async throws -> [Loop] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM loops
                WHERE status IN ('running', 'blocked', 'paused')
                ORDER BY last_activity_at DESC
            """)
            return rows.compactMap(Self.decode)
        }
    }

    public func recentLoops(limit: Int = 50) async throws -> [Loop] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM loops
                ORDER BY started_at DESC
                LIMIT ?
            """, arguments: [limit])
            return rows.compactMap(Self.decode)
        }
    }

    public func delete(_ id: String) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: "DELETE FROM loops WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Row decoding

    private static func decode(_ row: Row) -> Loop? {
        let filesJSON: String = row["files_changed"] ?? "[]"
        let cmdsJSON: String = row["commands_run"] ?? "[]"
        let testsJSON: String = row["tests_run"] ?? "[]"
        let proofJSON: String? = row["proof"]

        let files = (try? JSONDecoder().decode([String].self, from: Data(filesJSON.utf8))) ?? []
        let cmds = (try? JSONDecoder().decode([String].self, from: Data(cmdsJSON.utf8))) ?? []
        let tests = (try? JSONDecoder().decode([Loop.TestResult].self, from: Data(testsJSON.utf8))) ?? []
        let proof = proofJSON.flatMap { (try? JSONDecoder().decode(Loop.Proof.self, from: Data($0.utf8))) }

        let inputTokens: Int = row["input_tokens"] ?? 0
        let outputTokens: Int = row["output_tokens"] ?? 0
        let tokenUsage: Loop.TokenUsage? = (inputTokens > 0 || outputTokens > 0)
            ? Loop.TokenUsage(inputTokens: inputTokens, outputTokens: outputTokens)
            : nil

        let statusStr: String = row["status"] ?? "running"
        let status = Loop.Status(rawValue: statusStr) ?? .running

        let blockedReasonStr: String? = row["blocked_reason"]
        let blockedReason = blockedReasonStr.flatMap { try? JSONDecoder().decode(BlockedReason.self, from: Data($0.utf8)) }

        return Loop(
            id: row["id"] ?? "",
            goal: row["goal"] ?? "",
            plan: row["plan"],
            currentStep: row["current_step"],
            blockedReason: blockedReason,
            agent: row["agent"] ?? "",
            vendor: row["vendor"],
            model: row["model"],
            hostID: row["host_id"] ?? "",
            repo: row["repo"],
            branch: row["branch"],
            worktree: row["worktree"],
            filesChanged: files,
            commandsRun: cmds,
            testsRun: tests,
            approvalsAsked: row["approvals_asked"] ?? 0,
            approvalsDecided: row["approvals_decided"] ?? 0,
            policyExceptions: row["policy_exceptions"] ?? 0,
            spendUSD: row["spend_usd"] ?? 0,
            tokenCount: tokenUsage,
            status: status,
            startedAt: row["started_at"] ?? .now,
            completedAt: row["completed_at"],
            lastActivityAt: row["last_activity_at"],
            proof: proof
        )
    }
}
