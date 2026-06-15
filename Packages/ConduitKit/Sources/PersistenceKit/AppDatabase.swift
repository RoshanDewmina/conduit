import Foundation
import GRDB
import ConduitCore

/// Wraps the GRDB database stack. Repositories take a `DatabaseWriter` and
/// implement domain operations. Migrations are append-only.
public final class AppDatabase: Sendable {
    public let dbWriter: any DatabaseWriter

    public init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try Self.migrator.migrate(dbWriter)
    }

    // MARK: - Bootstrap

    public static func openShared() throws -> AppDatabase {
        let url = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Conduit/db.sqlite")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var config = Configuration()
        config.defaultTransactionKind = .immediate
        let pool = try DatabasePool(path: url.path, configuration: config)
        return try AppDatabase(pool)
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(try DatabaseQueue())
    }

    /// Deletes all user data — used by Settings → Reset app. Each table is
    /// cleared independently so a not-yet-migrated table cannot abort the wipe.
    public func wipeAll() async throws {
        try await dbWriter.write { db in
            for table in ["approvals", "blocks", "patches", "session_snapshots",
                          "sync_tombstones", "audit_events", "loops",
                          "snippets", "hosts"] {
                try? db.execute(sql: "DELETE FROM \(table)")
            }
        }
    }

    // MARK: - Migrations

    private static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        #if DEBUG
        m.eraseDatabaseOnSchemaChange = true
        #endif

        m.registerMigration("v1") { db in
            try db.create(table: "hosts") { t in
                t.column("id",                  .text).primaryKey()
                t.column("name",                .text).notNull()
                t.column("hostname",            .text).notNull()
                t.column("port",                .integer).notNull()
                t.column("username",            .text).notNull()
                t.column("authMethodType",      .text).notNull()
                t.column("authMethodKeyTag",    .text)
                t.column("tags",                .text).notNull().defaults(to: "[]")
                t.column("hostKeyFingerprint",  .text)
                t.column("preferredShell",      .text)
                t.column("tmuxSessionName",     .text)
                t.column("createdAt",           .datetime).notNull()
                t.column("lastConnectedAt",     .datetime)
            }
            try db.create(table: "blocks") { t in
                t.column("id",         .text).primaryKey()
                t.column("sessionId",  .text).notNull().indexed()
                t.column("hostName",   .text).notNull()
                t.column("cwd",        .text).notNull()
                t.column("command",    .text).notNull()
                t.column("output",     .text).notNull()
                t.column("exitCode",   .integer)
                t.column("startedAt",  .datetime).notNull()
                t.column("finishedAt", .datetime)
                t.column("isStarred",  .boolean).notNull().defaults(to: false)
            }
            try db.create(virtualTable: "blocks_fts", using: FTS5()) { t in
                t.column("command")
                t.column("output")
                t.tokenizer = .porter()
            }
            try db.create(table: "snippets") { t in
                t.column("id",         .text).primaryKey()
                t.column("name",       .text).notNull().indexed()
                t.column("body",       .text).notNull()
                t.column("hostTags",   .text).notNull().defaults(to: "[]")
                t.column("tags",       .text).notNull().defaults(to: "[]")
                t.column("createdAt",  .datetime).notNull()
                t.column("lastUsedAt", .datetime)
            }
            try db.create(table: "approvals") { t in
                t.column("id",         .text).primaryKey()
                t.column("sessionId",  .text).notNull().indexed()
                t.column("agent",      .text).notNull()
                t.column("kind",       .text).notNull()
                t.column("command",    .text)
                t.column("patch",      .text)
                t.column("cwd",        .text).notNull()
                t.column("risk",       .integer).notNull()
                t.column("createdAt",  .datetime).notNull()
                t.column("decidedAt",  .datetime)
                t.column("decision",   .text)
            }
        }

        m.registerMigration("v2") { db in
            try db.create(table: "patches") { t in
                t.column("id",          .text).primaryKey()
                t.column("sessionId",   .text).notNull().indexed()
                t.column("agent",       .text).notNull()
                t.column("unifiedDiff", .text).notNull()
                t.column("createdAt",   .datetime).notNull()
                t.column("decidedAt",   .datetime)
                t.column("decision",    .text)
            }
        }

        // Tier 1.4 + 1.5.2 (agent session resume + per-host startup command).
        m.registerMigration("v3") { db in
            try db.alter(table: "hosts") { t in
                t.add(column: "startupCommand", .text)
                t.add(column: "autoResume", .boolean).notNull().defaults(to: true)
            }
            try db.create(table: "session_snapshots") { t in
                t.column("hostID",                .text).primaryKey()
                t.column("lastUsedTime",          .datetime).notNull()
                t.column("agentID",               .text)
                t.column("agentSessionID",        .text)
                t.column("agentWorkingDirectory", .text)
                t.column("tmuxSessionName",       .text)
                t.foreignKey(["hostID"], references: "hosts", onDelete: .cascade)
            }
        }

        // Tier 2.1 + 2.3 + 2.4 (parameterized snippets + history back-link +
        // palette ranking).
        m.registerMigration("v4") { db in
            try db.alter(table: "snippets") { t in
                t.add(column: "arguments", .text).notNull().defaults(to: "[]")
                t.add(column: "useCount",  .integer).notNull().defaults(to: 0)
            }
            try db.alter(table: "blocks") { t in
                t.add(column: "originatingSnippetID", .text)
            }
        }

        // Bidirectional iCloud sync — LWW timestamps, key hints, deletion tombstones.
        m.registerMigration("v5") { db in
            try db.alter(table: "hosts") { t in
                t.add(column: "modifiedAt",    .datetime)
                t.add(column: "syncedKeyHint", .text)
            }
            try db.alter(table: "snippets") { t in
                t.add(column: "modifiedAt", .datetime)
            }
            // Tombstones track locally-deleted records so SyncEngine can
            // propagate deletions to CloudKit on the next push cycle.
            try db.create(table: "sync_tombstones") { t in
                t.column("id",          .text).notNull()
                t.column("recordType",  .text).notNull()
                t.column("deletedAt",   .datetime).notNull()
                t.primaryKey(["id", "recordType"])
            }
            // Back-fill: use best available proxy timestamp.
            try db.execute(sql: "UPDATE hosts SET modifiedAt = COALESCE(lastConnectedAt, createdAt)")
            try db.execute(sql: "UPDATE snippets SET modifiedAt = COALESCE(lastUsedAt, createdAt)")
        }

        // Tier 3.1 (security audit log). Registered after the sync migration so
        // both features coexist (sync = v5, audit = v6).
        m.registerMigration("v6") { db in
            try db.create(table: "audit_events") { t in
                t.column("id",        .text).primaryKey()
                t.column("hostId",    .text).notNull().indexed()
                t.column("type",      .text).notNull().indexed()
                t.column("metadata",  .text).notNull().defaults(to: "{}")
                t.column("createdAt", .datetime).notNull().indexed()
            }
        }

        // WS-C: structured tool-use fields for approvals (from Claude Code / Codex hooks).
        m.registerMigration("v7") { db in
            try db.alter(table: "approvals") { t in
                t.add(column: "tool_name",        .text)
                t.add(column: "tool_use_id",      .text)
                t.add(column: "agent_session_id", .text)
                t.add(column: "tool_input",       .text)
            }
        }

        // Governed Approvals: persist the blast-radius escalation context + the
        // ask-question fields so the governance banner / choice UI survive the
        // DB round-trip (the live VM re-reads from the DB via observe()).
        // Previously dropped on encode/decode → banner never rendered (MAJOR-7).
        m.registerMigration("v8") { db in
            try db.alter(table: "approvals") { t in
                t.add(column: "blast_radius",    .text)   // JSON ApprovalBlastRadius
                t.add(column: "question",        .text)
                t.add(column: "choices",         .text)   // JSON [String]
                t.add(column: "answered_choice", .integer)
            }
        }

        // Loop Object — first-class record of agent work sessions.
        m.registerMigration("v9") { db in
            try db.create(table: "loops") { t in
                t.column("id",                 .text).primaryKey()
                t.column("goal",               .text).notNull()
                t.column("plan",               .text)
                t.column("current_step",       .text)
                t.column("blocked_reason",     .text)
                t.column("agent",              .text).notNull()
                t.column("vendor",             .text)
                t.column("model",              .text)
                t.column("host_id",            .text).notNull()
                t.column("repo",               .text)
                t.column("branch",             .text)
                t.column("worktree",           .text)
                t.column("files_changed",      .text).notNull().defaults(to: "[]")
                t.column("commands_run",       .text).notNull().defaults(to: "[]")
                t.column("tests_run",          .text).notNull().defaults(to: "[]")
                t.column("approvals_asked",    .integer).notNull().defaults(to: 0)
                t.column("approvals_decided",  .integer).notNull().defaults(to: 0)
                t.column("policy_exceptions",  .integer).notNull().defaults(to: 0)
                t.column("spend_usd",          .real).notNull().defaults(to: 0)
                t.column("input_tokens",       .integer).notNull().defaults(to: 0)
                t.column("output_tokens",      .integer).notNull().defaults(to: 0)
                t.column("status",             .text).notNull().defaults(to: "running")
                t.column("started_at",         .datetime).notNull()
                t.column("completed_at",       .datetime)
                t.column("last_activity_at",   .datetime)
                t.column("proof",              .text)
                t.column("created_at",         .datetime).notNull().defaults(to: "CURRENT_TIMESTAMP")
                t.column("updated_at",         .datetime).notNull().defaults(to: "CURRENT_TIMESTAMP")
            }
        }

        return m
    }
}
