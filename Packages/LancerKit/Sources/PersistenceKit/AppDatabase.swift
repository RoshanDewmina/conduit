import Foundation
import GRDB
import LancerCore

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
        let url = try sharedDatabaseURL()
        var config = Configuration()
        config.defaultTransactionKind = .immediate
        // Multiple processes (main app, LancerWidgets extension — Live
        // Activity / Lock Screen `ApprovalActionIntent` runs there, not in
        // the main app process) now open the same physical file. GRDB's
        // DatabasePool already uses WAL, which supports concurrent
        // multi-process readers/writers; give a contending writer a few
        // seconds to retry instead of failing immediately with SQLITE_BUSY.
        config.busyMode = .timeout(5)
        let pool = try DatabasePool(path: url.path, configuration: config)
        return try AppDatabase(pool)
    }

    /// Resolves the single physical database file every process that touches
    /// Lancer's local data must share: the main app, the `LancerWidgets`
    /// extension (a `LiveActivityIntent` such as `ApprovalActionIntent` runs
    /// in the widget extension's own process, not the main app's — see its
    /// doc comment), and the Watch companion. Must live in the App Group
    /// container (`group.dev.lancer.mobile`, already used for
    /// `WidgetSnapshot`'s `UserDefaults`), not `.applicationSupportDirectory`
    /// — that path is scoped to the calling process's own private sandbox
    /// container, so a decision made from the Lock Screen / Dynamic Island
    /// used to land in a throwaway database the main app could never see,
    /// leaving its local row permanently "pending" even though the decision
    /// correctly reached the daemon over the network — the root cause of the
    /// Home Screen widget showing an inflated approval count with a stale
    /// summary line (`docs/test-runs/` widget investigation).
    private static func sharedDatabaseURL() throws -> URL {
        guard let groupContainer = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroupID
        ) else {
            throw LancerError.databaseFailure(detail: "app group container unavailable")
        }
        let dir = groupContainer.appendingPathComponent("Lancer", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let newURL = dir.appendingPathComponent("db.sqlite")

        // One-time migration for existing installs: earlier builds stored
        // the database in the main app's private Application Support
        // directory. Copy it (plus GRDB's WAL/SHM sidecar files, so no
        // recently-committed rows are lost) into the App Group container the
        // first time this runs, so upgrading users keep their history
        // instead of silently starting from an empty database.
        if !FileManager.default.fileExists(atPath: newURL.path) {
            migrateLegacyDatabaseIfNeeded(into: dir, newURL: newURL, legacyURLOverride: nil)
        }
        return newURL
    }

    /// Performs the one-time legacy-database migration `sharedDatabaseURL()`
    /// triggers. Failure-safe by construction, unlike a naive `try?`-per-file
    /// copy: every file that exists at the legacy location is first copied to
    /// a `.migrating-<uuid>` temp name inside the SAME destination directory
    /// (so the later rename is a same-volume atomic move, not a cross-volume
    /// copy), and only once every copy has fully succeeded are any of them
    /// renamed into their real names — sidecars (`-wal`/`-shm`) before
    /// `db.sqlite` itself, so no other process can ever observe `db.sqlite`
    /// at its final path before its sidecars are already there (matters
    /// because `sharedDatabaseURL()`'s caller gates entirely on whether
    /// `db.sqlite` exists). If any copy fails partway, every staged temp file
    /// is removed and the function returns with `newURL` still not
    /// existing — the legacy source is never touched, and `openShared()`
    /// will simply retry this same migration on the next launch rather than
    /// silently leaving a partial or empty database at the real path (the
    /// failure mode a bare `try?` produced before this fix: a disk-pressure
    /// or interrupted-copy error was swallowed, `db.sqlite` could end up
    /// present-but-empty, and the "does the file exist" completion check
    /// would treat that as "already migrated" forever, permanently losing
    /// the user's local history with no error surfaced anywhere).
    /// `legacyURLOverride` exists purely so tests can point this at a temp
    /// directory instead of the real per-app Application Support directory —
    /// production always passes `nil` (the real path is resolved below).
    /// `internal` (not `private`) for the same reason: `@testable import`
    /// only reaches non-`private` declarations.
    static func migrateLegacyDatabaseIfNeeded(into dir: URL, newURL: URL, legacyURLOverride: URL?) {
        let resolvedLegacyURL = legacyURLOverride ?? (try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("Lancer/db.sqlite"))
        guard let legacyURL = resolvedLegacyURL,
            FileManager.default.fileExists(atPath: legacyURL.path)
        else { return }

        let tempSuffix = "migrating-\(UUID().uuidString)"
        var staged: [(temp: URL, finalName: String)] = []

        func stageIfPresent(sourcePath: String, finalName: String) -> Bool {
            guard FileManager.default.fileExists(atPath: sourcePath) else {
                return true // sidecar legitimately absent; not a failure
            }
            let temp = dir.appendingPathComponent("\(finalName).\(tempSuffix)")
            do {
                try FileManager.default.copyItem(at: URL(fileURLWithPath: sourcePath), to: temp)
                staged.append((temp, finalName))
                return true
            } catch {
                return false
            }
        }

        func cleanupStaged() {
            for entry in staged {
                try? FileManager.default.removeItem(at: entry.temp)
            }
        }

        // Stage sidecars and the main file under temp names before renaming
        // anything — a failure here leaves zero trace at the final paths.
        let sidecarsOK = stageIfPresent(sourcePath: legacyURL.path + "-wal", finalName: "db.sqlite-wal")
            && stageIfPresent(sourcePath: legacyURL.path + "-shm", finalName: "db.sqlite-shm")
        guard sidecarsOK, stageIfPresent(sourcePath: legacyURL.path, finalName: "db.sqlite") else {
            cleanupStaged()
            return
        }

        // Rename into place: sidecars first, `db.sqlite` last.
        let sidecarEntries = staged.filter { $0.finalName != "db.sqlite" }
        let mainEntry = staged.first { $0.finalName == "db.sqlite" }
        for entry in sidecarEntries + (mainEntry.map { [$0] } ?? []) {
            do {
                try FileManager.default.moveItem(at: entry.temp, to: dir.appendingPathComponent(entry.finalName))
            } catch {
                // A sidecar or the main file failed to rename after a
                // successful copy (rare — same-volume rename after we just
                // wrote the temp file). Clean up whatever is still staged;
                // any sidecar(s) already renamed before this failure are
                // harmless orphans (inert without db.sqlite present) until a
                // future successful migration attempt overwrites them.
                cleanupStaged()
                return
            }
        }
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(try DatabaseQueue())
    }

    /// Deletes all user data — used by Settings → Reset app. Each table is
    /// cleared independently so a not-yet-migrated table cannot abort the wipe.
    public func wipeAll() async throws {
        try await dbWriter.write { db in
            for table in ["chat_events", "chat_drafts", "chat_artifacts", "chat_turns", "chat_conversations",
                          "approvals", "blocks", "patches", "session_snapshots",
                          "sync_tombstones", "audit_events", "loops",
                          "snippets", "hosts", "workspaces"] {
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

        // Durable chat persistence — conversations, turns, artifacts, FTS.
        m.registerMigration("v10") { db in
            try db.create(table: "chat_conversations") { t in
                t.column("id",                  .text).primaryKey()
                t.column("title",               .text).notNull()
                t.column("agent_id",            .text).notNull()
                t.column("vendor",              .text)
                t.column("host_name",           .text).notNull()
                t.column("host_id",             .text)
                t.column("cwd",                 .text).notNull()
                t.column("model",               .text)
                t.column("budget_usd",          .real)
                t.column("status",              .text).notNull().defaults(to: "active")
                t.column("created_at",          .datetime).notNull().defaults(to: "CURRENT_TIMESTAMP")
                t.column("updated_at",          .datetime).notNull().defaults(to: "CURRENT_TIMESTAMP")
                t.column("last_activity_at",    .datetime).notNull().defaults(to: "CURRENT_TIMESTAMP")
            }
            try db.create(index: "idx_chat_conv_last_activity", on: "chat_conversations", columns: ["last_activity_at"])
            try db.create(index: "idx_chat_conv_status", on: "chat_conversations", columns: ["status"])
            try db.create(index: "idx_chat_conv_agent", on: "chat_conversations", columns: ["agent_id"])
            try db.create(index: "idx_chat_conv_host", on: "chat_conversations", columns: ["host_name"])

            try db.create(table: "chat_turns") { t in
                t.column("id",              .text).primaryKey()
                t.column("conversation_id", .text).notNull().indexed()
                t.column("ordinal",         .integer).notNull()
                t.column("prompt",          .text).notNull()
                t.column("run_id",          .text).notNull()
                t.column("transport_kind",  .text).notNull().defaults(to: "ssh")
                t.column("status",          .text).notNull().defaults(to: "running")
                t.column("assistant_text",  .text).notNull().defaults(to: "")
                t.column("error_message",   .text)
                t.column("created_at",      .datetime).notNull().defaults(to: "CURRENT_TIMESTAMP")
                t.column("completed_at",    .datetime)
                t.foreignKey(["conversation_id"], references: "chat_conversations", onDelete: .cascade)
            }
            try db.create(index: "idx_chat_turn_run", on: "chat_turns", columns: ["run_id"])

            try db.create(table: "chat_artifacts") { t in
                t.column("id",              .text).primaryKey()
                t.column("conversation_id", .text).notNull().indexed()
                t.column("turn_id",         .text).notNull()
                t.column("run_id",          .text).notNull()
                t.column("kind",            .text).notNull()
                t.column("title",           .text).notNull()
                t.column("summary",         .text)
                t.column("payload_json",    .text).notNull().defaults(to: "{}")
                t.column("status",          .text).notNull().defaults(to: "running")
                t.column("created_at",      .datetime).notNull().defaults(to: "CURRENT_TIMESTAMP")
                t.column("updated_at",      .datetime).notNull().defaults(to: "CURRENT_TIMESTAMP")
                t.foreignKey(["conversation_id"], references: "chat_conversations", onDelete: .cascade)
                t.foreignKey(["turn_id"], references: "chat_turns", onDelete: .cascade)
            }
            try db.create(index: "idx_chat_art_run", on: "chat_artifacts", columns: ["run_id"])
            try db.create(index: "idx_chat_art_kind", on: "chat_artifacts", columns: ["kind"])
            try db.create(index: "idx_chat_art_status", on: "chat_artifacts", columns: ["status"])

            try db.create(virtualTable: "chat_fts", using: FTS5()) { t in
                t.column("conversation_id")
                t.column("title")
                t.column("prompt")
                t.column("assistant_text")
                t.column("artifact_text")
                t.tokenizer = .porter()
            }
        }

        // Content-hash binding (security audit): persists the daemon's
        // `computeContentHash` over (command, patch, cwd, toolInput) so it
        // survives the DB round-trip and can be echoed back with a decision —
        // without this column, every approval read via observe()/all() loses
        // contentHash and lancerd's approvalStore.resolve rejects the decision.
        m.registerMigration("v11") { db in
            try db.alter(table: "approvals") { t in
                t.add(column: "content_hash", .text)
            }
        }

        // Workspace — a persisted, named project directory scoped to a machine
        // (the Machine → Workspace → Chat middle layer). Replaces the flat,
        // unscoped `lancer.recentProjectPaths` AppStorage cache in
        // NewChatTabView with a real, listable, renameable record.
        m.registerMigration("v12") { db in
            try db.create(table: "workspaces") { t in
                t.column("id",           .text).primaryKey()
                t.column("name",         .text).notNull()
                t.column("machine_id",   .text).notNull()
                t.column("path",         .text).notNull()
                t.column("last_branch",  .text)
                t.column("created_at",   .datetime).notNull().defaults(to: "CURRENT_TIMESTAMP")
                t.column("last_used_at", .datetime).notNull().defaults(to: "CURRENT_TIMESTAMP")
            }
            try db.create(index: "idx_workspaces_machine", on: "workspaces", columns: ["machine_id"])
            try db.create(index: "idx_workspaces_last_used", on: "workspaces", columns: ["last_used_at"])
        }

        // Cross-device conversation sync (Task 6, build handoff): extends the
        // local chat tables into a mirror of the host-owned conversation
        // ledger instead of the sole source of truth. Existing rows default
        // to sync_state='localOnly' (pre-sync conversations, or ones never
        // bound to a host ledger row) so nothing already on-device is
        // reinterpreted as host-backed until it is actually re-fetched.
        m.registerMigration("v13") { db in
            try db.alter(table: "chat_conversations") { t in
                t.add(column: "source_host_id", .text)
                t.add(column: "source_host_name", .text)
                t.add(column: "last_host_seq", .integer).notNull().defaults(to: 0)
                t.add(column: "sync_state", .text).notNull().defaults(to: "localOnly")
                t.add(column: "cloud_record_name", .text)
                t.add(column: "cloud_uploaded_at", .datetime)
                t.add(column: "cloud_modified_at", .datetime)
                t.add(column: "archived_at", .datetime)
            }
            try db.create(index: "idx_chat_conv_sync_state", on: "chat_conversations", columns: ["sync_state"])

            try db.alter(table: "chat_turns") { t in
                t.add(column: "client_turn_id", .text)
                t.add(column: "vendor_session_id", .text)
                t.add(column: "host_seq_start", .integer)
                t.add(column: "host_seq_end", .integer)
                t.add(column: "cloud_record_name", .text)
            }
            try db.create(index: "idx_chat_turn_vendor_session", on: "chat_turns", columns: ["vendor_session_id"])

            // Append-only mirror of the host's conversation_events log.
            // Primary key (conversation_id, seq) makes re-fetching an
            // overlapping range idempotent (INSERT OR IGNORE at the
            // repository layer) instead of duplicating rows.
            try db.create(table: "chat_events") { t in
                t.column("conversation_id", .text).notNull()
                t.column("seq",             .integer).notNull()
                t.column("turn_id",         .text)
                t.column("run_id",          .text)
                t.column("kind",            .text).notNull()
                t.column("role",            .text)
                t.column("stream",          .text)
                t.column("text",            .text)
                t.column("payload_json",    .text)
                t.column("created_at",      .datetime).notNull().defaults(to: "CURRENT_TIMESTAMP")
                t.primaryKey(["conversation_id", "seq"])
                t.foreignKey(["conversation_id"], references: "chat_conversations", onDelete: .cascade)
            }

            // One unsent local draft per conversation — explicit, never
            // auto-sent (product semantics #5: no silent offline execution
            // queue). Saving a new draft overwrites the prior one.
            try db.create(table: "chat_drafts") { t in
                t.column("conversation_id", .text).primaryKey()
                t.column("text",            .text).notNull()
                t.column("saved_at",        .datetime).notNull().defaults(to: "CURRENT_TIMESTAMP")
                t.foreignKey(["conversation_id"], references: "chat_conversations", onDelete: .cascade)
            }
        }

        // Structured chat attachments — metadata only; preview bytes live in
        // AttachmentPreviewCache. Old rows decode as [] via DEFAULT.
        m.registerMigration("v14") { db in
            try db.alter(table: "chat_turns") { t in
                t.add(column: "attachments_json", .text).notNull().defaults(to: "[]")
            }
        }

        return m
    }
}
