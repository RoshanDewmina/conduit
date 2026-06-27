import Foundation
@preconcurrency import Citadel
@preconcurrency import NIOCore
import LancerCore

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
        do {
            return try await listUsingSFTP(path: path)
        } catch {
            guard Self.isDirectoryEOF(error) else { throw error }
            return try await listUsingShellFallback(path: path)
        }
    }

    private func listUsingSFTP(path: String) async throws -> [SFTPEntry] {
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

                    entries.append(SFTPEntry(
                        name: filename,
                        path: Self.join(parent: path, child: filename),
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

    private func listUsingShellFallback(path: String) async throws -> [SFTPEntry] {
        let out = try await session.executeCollected("ls -la --time-style=long-iso \(Self.shellQuote(Self.shellPath(path)))")
        return Self.parseLongListing(out, parent: path)
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

    /// Downloads data from a remote file, reporting optional transfer progress.
    public func download(
        path: String,
        limitBytes: Int = 50 * 1024 * 1024,
        onProgress: (@Sendable (FileTransferProgress) -> Void)? = nil
    ) async throws -> Data {
        try await session.withSFTP { sftp in
            let attrs = try await sftp.getAttributes(at: path)
            let total = attrs.size.map(Int64.init)
            return try await sftp.withFile(filePath: path, flags: .read) { file in
                var offset: UInt64 = 0
                var received: Int64 = 0
                var result = Data()
                let chunkSize: UInt32 = 32_000

                while received < Int64(limitBytes) {
                    let requested = UInt32(Swift.min(Int(chunkSize), limitBytes - Int(received)))
                    if requested == 0 { break }
                    var chunk = try await file.read(from: offset, length: requested)
                    let bytes = chunk.readableBytes
                    if bytes == 0 { break }
                    guard let data = chunk.readBytes(length: bytes) else { break }
                    result.append(contentsOf: data)
                    received += Int64(bytes)
                    offset += UInt64(bytes)
                    onProgress?(FileTransferProgress(bytesTransferred: received, totalBytes: total))
                }
                return result
            }
        }
    }

    /// Streams a local file to a remote path over SFTP.
    public func upload(
        localFileURL: URL,
        to remotePath: String,
        onProgress: (@Sendable (FileTransferProgress) -> Void)? = nil
    ) async throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: localFileURL.path)
        let totalBytes = (attrs[.size] as? NSNumber)?.int64Value
        let handle = try FileHandle(forReadingFrom: localFileURL)
        defer { try? handle.close() }

        try await session.withSFTP { sftp in
            try await sftp.withFile(filePath: remotePath, flags: [.write, .create, .truncate]) { remote in
                var offset: UInt64 = 0
                var transferred: Int64 = 0
                let chunkSize = 32_000
                while true {
                    let data = try handle.read(upToCount: chunkSize) ?? Data()
                    if data.isEmpty { break }
                    var buffer = ByteBufferAllocator().buffer(capacity: data.count)
                    buffer.writeBytes(data)
                    try await remote.write(buffer, at: offset)
                    offset += UInt64(data.count)
                    transferred += Int64(data.count)
                    onProgress?(FileTransferProgress(bytesTransferred: transferred, totalBytes: totalBytes))
                }
            }
        }
    }

    /// Writes `data` to `path`, replacing any existing file.
    public func write(
        path: String,
        data: Data,
        onProgress: (@Sendable (FileTransferProgress) -> Void)? = nil
    ) async throws {
        try await session.withSFTP { sftp in
            try await sftp.withFile(filePath: path, flags: [.write, .create, .truncate]) { file in
                let chunkSize = 32_000
                var offset: UInt64 = 0
                var transferred = 0
                while transferred < data.count {
                    let end = Swift.min(transferred + chunkSize, data.count)
                    let chunk = data[transferred..<end]
                    var buffer = ByteBufferAllocator().buffer(capacity: chunk.count)
                    buffer.writeBytes(chunk)
                    try await file.write(buffer, at: offset)
                    transferred = end
                    offset += UInt64(chunk.count)
                    onProgress?(FileTransferProgress(
                        bytesTransferred: Int64(transferred),
                        totalBytes: Int64(data.count)
                    ))
                }
            }
        }
    }

    /// Removes a file at `path`.
    public func remove(path: String) async throws {
        try await session.withSFTP { sftp in
            try await sftp.remove(at: path)
        }
    }

    /// Renames a file or directory from `from` to `to`.
    public func rename(from: String, to: String) async throws {
        try await session.withSFTP { sftp in
            try await sftp.rename(at: from, to: to)
        }
    }

    /// Creates a directory at `path`.
    public func mkdir(path: String) async throws {
        try await session.withSFTP { sftp in
            try await sftp.createDirectory(atPath: path)
        }
    }

    /// Removes an empty directory at `path`.
    public func rmdir(path: String) async throws {
        try await session.withSFTP { sftp in
            try await sftp.rmdir(at: path)
        }
    }

    /// Applies Unix mode bits at `path` (e.g. `0o755`).
    public func chmod(path: String, mode: UInt32) async throws {
        try await session.withSFTP { sftp in
            var attrs = SFTPFileAttributes()
            attrs.permissions = mode
            try await sftp.setAttributes(at: path, to: attrs)
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

    nonisolated static func parseLongListing(_ output: String, parent: String) -> [SFTPEntry] {
        output.split(separator: "\n").compactMap { line -> SFTPEntry? in
            guard !line.hasPrefix("total ") else { return nil }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 8 else { return nil }

            let permissions = String(parts[0])
            var name = String(parts[7..<parts.count].joined(separator: " "))
            if let symlinkSeparator = name.range(of: " -> ") {
                name = String(name[..<symlinkSeparator.lowerBound])
            }
            guard name != "." && name != ".." else { return nil }

            return SFTPEntry(
                name: name,
                path: join(parent: parent, child: name),
                isDirectory: permissions.hasPrefix("d"),
                sizeBytes: Int(parts[4]),
                permissions: permissions
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    nonisolated private static func isDirectoryEOF(_ error: any Error) -> Bool {
        if let status = error as? SFTPMessage.Status {
            return status.errorCode == .eof
        }
        if case let SFTPError.errorStatus(status) = error {
            return status.errorCode == .eof
        }
        let description = String(describing: error).lowercased()
        return description.contains("sftpmessage.status error 1")
            || description.contains("ssh_fx_eof")
    }

    nonisolated private static func shellPath(_ path: String) -> String {
        path == "~" ? "." : path
    }

    nonisolated private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    nonisolated private static func join(parent: String, child: String) -> String {
        if parent.isEmpty || parent == "." { return "./\(child)" }
        if parent == "/" { return "/\(child)" }
        if parent.hasSuffix("/") { return "\(parent)\(child)" }
        return "\(parent)/\(child)"
    }
}
