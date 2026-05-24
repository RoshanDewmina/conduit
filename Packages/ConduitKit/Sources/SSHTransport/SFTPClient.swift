import Foundation
@preconcurrency import Citadel
import ConduitCore

// MARK: - SFTPEntry

public struct SFTPEntry: Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let sizeBytes: Int?
    public let permissions: String?
    public let modifiedAt: Date?

    public init(
        name: String,
        path: String,
        isDirectory: Bool,
        sizeBytes: Int? = nil,
        permissions: String? = nil,
        modifiedAt: Date? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.sizeBytes = sizeBytes
        self.permissions = permissions
        self.modifiedAt = modifiedAt
    }
}

// MARK: - SFTPClient

/// Actor providing SFTP file-system operations over an established `SSHSession`.
///
/// Each method opens a fresh SFTP subsystem channel via `SSHSession.withSFTP`,
/// performs the requested operation, and closes the channel before returning.
/// This keeps resource usage low and avoids holding a long-lived SFTP handle.
public actor SFTPClient {
    private let session: SSHSession

    public init(session: SSHSession) {
        self.session = session
    }

    // MARK: - Directory listing

    /// Returns the entries in the directory at `path`.
    ///
    /// - Parameter path: Absolute or relative remote path. Tilde expansion is
    ///   performed by the server (via SFTP realpath).
    public func list(path: String) async throws -> [SFTPEntry] {
        try await session.withSFTP { sftp in
            let names = try await sftp.listDirectory(atPath: path)
            // `listDirectory` returns a `[SFTPMessage.Name]`. Each Name contains
            // an array of `SFTPPathComponent` values. Flatten into a single list.
            var entries: [SFTPEntry] = []
            for name in names {
                for component in name.components {
                    let filename = component.filename
                    // Skip self and parent directory links
                    guard filename != "." && filename != ".." else { continue }

                    let attrs = component.attributes
                    let isDir = Self.isDirectory(permissions: attrs.permissions)
                    let sizeBytes = attrs.size.map { Int($0) }
                    let permStr = attrs.permissions.map { Self.permissionsString(from: $0) }
                    let modifiedAt = attrs.accessModificationTime?.modificationTime

                    // Build the full path by joining parent and filename
                    let fullPath: String
                    if path.hasSuffix("/") {
                        fullPath = path + filename
                    } else {
                        fullPath = path + "/" + filename
                    }

                    entries.append(SFTPEntry(
                        name: filename,
                        path: fullPath,
                        isDirectory: isDir,
                        sizeBytes: sizeBytes,
                        permissions: permStr,
                        modifiedAt: modifiedAt
                    ))
                }
            }
            // Sort: directories first, then alphabetically
            return entries.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }

    // MARK: - File reading

    /// Downloads up to `limitBytes` bytes from the remote file at `path`.
    ///
    /// - Parameters:
    ///   - path: Absolute or relative remote path.
    ///   - limitBytes: Maximum bytes to read (default 10 MiB).
    public func read(path: String, limitBytes: Int = 10 * 1024 * 1024) async throws -> Data {
        try await session.withSFTP { sftp in
            try await sftp.withFile(filePath: path, flags: .read) { file in
                var buf = try await file.readAll()
                // Clamp to limit
                let readable = buf.readableBytes
                let clamp = Swift.min(readable, limitBytes)
                guard let bytes = buf.readBytes(length: clamp) else { return Data() }
                return Data(bytes)
            }
        }
    }

    // MARK: - Stat

    /// Returns a single `SFTPEntry` describing the item at `path`.
    public func stat(path: String) async throws -> SFTPEntry {
        try await session.withSFTP { sftp in
            let attrs = try await sftp.getAttributes(at: path)
            let name = (path as NSString).lastPathComponent
            let isDir = Self.isDirectory(permissions: attrs.permissions)
            return SFTPEntry(
                name: name,
                path: path,
                isDirectory: isDir,
                sizeBytes: attrs.size.map { Int($0) },
                permissions: attrs.permissions.map { Self.permissionsString(from: $0) },
                modifiedAt: attrs.accessModificationTime?.modificationTime
            )
        }
    }

    // MARK: - Helpers (nonisolated, pure functions)

    /// Checks the Unix permission bits for the directory flag (S_IFDIR = 0o040000).
    nonisolated private static func isDirectory(permissions: UInt32?) -> Bool {
        guard let p = permissions else { return false }
        return (p & 0o170000) == 0o040000
    }

    /// Converts a Unix permission bitmask to an rwxrwxrwx string (e.g. "drwxr-xr-x").
    nonisolated private static func permissionsString(from mode: UInt32) -> String {
        let fileType: Character = {
            let fmt = mode & 0o170000
            switch fmt {
            case 0o040000: return "d"
            case 0o120000: return "l"
            case 0o100000: return "-"
            default:       return "?"
            }
        }()
        func rwx(_ bits: UInt32, r: UInt32, w: UInt32, x: UInt32) -> String {
            let rs: Character = (bits & r) != 0 ? "r" : "-"
            let ws: Character = (bits & w) != 0 ? "w" : "-"
            let xs: Character = (bits & x) != 0 ? "x" : "-"
            return "\(rs)\(ws)\(xs)"
        }
        let user  = rwx(mode, r: 0o400, w: 0o200, x: 0o100)
        let group = rwx(mode, r: 0o040, w: 0o020, x: 0o010)
        let other = rwx(mode, r: 0o004, w: 0o002, x: 0o001)
        return "\(fileType)\(user)\(group)\(other)"
    }
}
