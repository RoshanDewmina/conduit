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

        return m
    }
}
