import Foundation
import GRDB
import ConduitCore

public actor BlockRepository {
    private let db: AppDatabase
    public init(_ db: AppDatabase) { self.db = db }

    public func persist(_ block: Block) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO blocks (id, sessionId, hostName, cwd, command, output, exitCode,
                                    startedAt, finishedAt, isStarred, originatingSnippetID)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  output = excluded.output,
                  exitCode = excluded.exitCode,
                  finishedAt = excluded.finishedAt,
                  isStarred = excluded.isStarred,
                  originatingSnippetID = excluded.originatingSnippetID
            """, arguments: [
                block.id.uuidString,
                block.sessionID.uuidString,
                block.prompt.hostName,
                block.prompt.cwd,
                block.command,
                block.joinedOutput,
                block.exitStatus?.code,
                block.startedAt,
                block.finishedAt,
                block.isStarred,
                block.originatingSnippetID?.uuidString,
            ])

            // Keep the FTS index in sync with the (possibly upserted) block row.
            // Streaming updates re-persist the same block id, so delete any prior
            // FTS row for this rowid before re-inserting — otherwise the index
            // accumulates stale duplicate rows and search misses the latest output.
            try db.execute(sql: """
                DELETE FROM blocks_fts WHERE rowid = (SELECT rowid FROM blocks WHERE id = ?)
            """, arguments: [block.id.uuidString])
            try db.execute(sql: """
                INSERT INTO blocks_fts (rowid, command, output)
                VALUES ((SELECT rowid FROM blocks WHERE id = ?), ?, ?)
            """, arguments: [
                block.id.uuidString,
                block.command,
                block.joinedOutput,
            ])
        }
    }

    public func search(_ query: String, limit: Int = 50) async throws -> [Block] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT blocks.* FROM blocks
                JOIN blocks_fts ON blocks_fts.rowid = blocks.rowid
                WHERE blocks_fts MATCH ?
                ORDER BY startedAt DESC
                LIMIT ?
            """, arguments: [query, limit])
            return rows.compactMap(Self.decode)
        }
    }

    public func recent(for sessionID: SessionID, limit: Int = 200) async throws -> [Block] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM blocks WHERE sessionId = ?
                ORDER BY startedAt DESC LIMIT ?
            """, arguments: [sessionID.uuidString, limit])
            return rows.compactMap(Self.decode)
        }
    }

    private static func decode(_ row: Row) -> Block? {
        guard
            let idStr: String = row["id"], let id = UUID(uuidString: idStr),
            let sidStr: String = row["sessionId"], let sid = UUID(uuidString: sidStr)
        else { return nil }
        let prompt = Block.PromptInfo(
            cwd: row["cwd"] ?? "",
            hostName: row["hostName"] ?? ""
        )
        let chunks: [BlockChunk] = (row["output"] as String?).map {
            [BlockChunk(text: $0, stream: .stdout)]
        } ?? []
        let exit = (row["exitCode"] as Int?).map(ExitStatus.init)
        // Blocks loaded from the database are always finished (state = .done).
        let exitCode = (row["exitCode"] as Int?) ?? 0
        let snippetID = (row["originatingSnippetID"] as String?).flatMap(UUID.init).map(SnippetID.init)
        return Block(
            id: BlockID(id),
            sessionID: SessionID(sid),
            prompt: prompt,
            command: row["command"] ?? "",
            chunks: chunks,
            exitStatus: exit,
            startedAt: row["startedAt"] ?? .now,
            finishedAt: row["finishedAt"],
            isStarred: row["isStarred"] ?? false,
            originatingSnippetID: snippetID,
            state: .done(exitCode: exitCode)
        )
    }
}
