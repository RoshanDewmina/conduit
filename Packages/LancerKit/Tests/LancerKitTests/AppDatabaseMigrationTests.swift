import Foundation
import Testing
@testable import PersistenceKit

/// Covers `AppDatabase.migrateLegacyDatabaseIfNeeded` — the App-Group DB
/// migration flagged in review as failure-unsafe (silent `try?`, no
/// atomicity across db.sqlite + its -wal/-shm sidecars). Uses temp
/// directories via `legacyURLOverride` instead of the real per-app
/// Application Support directory / App Group container, neither of which is
/// reachable from a plain SPM test target without real entitlements.
struct AppDatabaseMigrationTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppDatabaseMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func migratesMainFileAndBothSidecars() throws {
        let legacyDir = try makeTempDir()
        let destDir = try makeTempDir()
        let legacyURL = legacyDir.appendingPathComponent("db.sqlite")
        try Data("main-db-contents".utf8).write(to: legacyURL)
        try Data("wal-contents".utf8).write(to: URL(fileURLWithPath: legacyURL.path + "-wal"))
        try Data("shm-contents".utf8).write(to: URL(fileURLWithPath: legacyURL.path + "-shm"))

        let newURL = destDir.appendingPathComponent("db.sqlite")
        AppDatabase.migrateLegacyDatabaseIfNeeded(into: destDir, newURL: newURL, legacyURLOverride: legacyURL)

        #expect(FileManager.default.fileExists(atPath: newURL.path))
        #expect(try Data(contentsOf: newURL) == Data("main-db-contents".utf8))
        #expect(FileManager.default.fileExists(atPath: newURL.path + "-wal"))
        #expect(try Data(contentsOf: URL(fileURLWithPath: newURL.path + "-wal")) == Data("wal-contents".utf8))
        #expect(FileManager.default.fileExists(atPath: newURL.path + "-shm"))
        // No leftover temp files.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: destDir.path)
            .filter { $0.contains("migrating-") }
        #expect(leftovers.isEmpty)
    }

    @Test func migratesMainFileWithoutSidecars() throws {
        let legacyDir = try makeTempDir()
        let destDir = try makeTempDir()
        let legacyURL = legacyDir.appendingPathComponent("db.sqlite")
        try Data("main-only".utf8).write(to: legacyURL)
        // No -wal/-shm files created — a clean checkpoint before migration.

        let newURL = destDir.appendingPathComponent("db.sqlite")
        AppDatabase.migrateLegacyDatabaseIfNeeded(into: destDir, newURL: newURL, legacyURLOverride: legacyURL)

        #expect(FileManager.default.fileExists(atPath: newURL.path))
        #expect(!FileManager.default.fileExists(atPath: newURL.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: newURL.path + "-shm"))
    }

    @Test func noLegacyFileIsANoOp() throws {
        let legacyDir = try makeTempDir()
        let destDir = try makeTempDir()
        let legacyURL = legacyDir.appendingPathComponent("db.sqlite") // never created

        let newURL = destDir.appendingPathComponent("db.sqlite")
        AppDatabase.migrateLegacyDatabaseIfNeeded(into: destDir, newURL: newURL, legacyURLOverride: legacyURL)

        #expect(!FileManager.default.fileExists(atPath: newURL.path))
    }

    /// The core failure-safety property: if copying the main db.sqlite fails
    /// partway (simulated here by making the legacy file unreadable), the
    /// migration must leave NOTHING at the destination — not a partial file,
    /// not an orphaned sidecar — so a later retry starts clean rather than
    /// treating a corrupt partial copy as "already migrated."
    @Test func failedMainCopyLeavesNoPartialState() throws {
        let legacyDir = try makeTempDir()
        let destDir = try makeTempDir()
        let legacyURL = legacyDir.appendingPathComponent("db.sqlite")
        try Data("main-db-contents".utf8).write(to: legacyURL)
        try Data("wal-contents".utf8).write(to: URL(fileURLWithPath: legacyURL.path + "-wal"))
        // Make the main file unreadable so its copy fails after the sidecar
        // copies have already succeeded — the exact partial-failure order
        // this fix is meant to handle safely.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: legacyURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: legacyURL.path) }

        let newURL = destDir.appendingPathComponent("db.sqlite")
        AppDatabase.migrateLegacyDatabaseIfNeeded(into: destDir, newURL: newURL, legacyURLOverride: legacyURL)

        #expect(!FileManager.default.fileExists(atPath: newURL.path))
        #expect(!FileManager.default.fileExists(atPath: newURL.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: newURL.path + "-shm"))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: destDir.path)
        #expect(leftovers.isEmpty, "expected no leftover temp/partial files, found \(leftovers)")
    }

    @Test func legacySourceIsNeverModifiedOrDeleted() throws {
        let legacyDir = try makeTempDir()
        let destDir = try makeTempDir()
        let legacyURL = legacyDir.appendingPathComponent("db.sqlite")
        try Data("main-db-contents".utf8).write(to: legacyURL)

        let newURL = destDir.appendingPathComponent("db.sqlite")
        AppDatabase.migrateLegacyDatabaseIfNeeded(into: destDir, newURL: newURL, legacyURLOverride: legacyURL)

        #expect(FileManager.default.fileExists(atPath: legacyURL.path))
        #expect(try Data(contentsOf: legacyURL) == Data("main-db-contents".utf8))
    }
}
