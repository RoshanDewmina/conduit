import Foundation

/// Pure attachment draft + upload helpers for the Context sheet / composer.
/// OS-agnostic so `swift test` can drive the chip state machine, chunking, and
/// prompt-prefix format without UIKit.

public enum AttachmentLimits {
    public static let maxFiles = 5
    public static let maxBytesPerFile = 20 * 1024 * 1024
    /// Pre-encryption chunk size for `attachment.put` (E2E + SSH).
    public static let maxChunkBytes = 256 * 1024
}

public enum AttachmentChipState: Equatable, Sendable {
    case pending
    case uploading(progress: Double)
    case done(hostPath: String)
    case error(message: String)

    public var isReadyToSend: Bool {
        if case .done = self { return true }
        return false
    }

    public var blocksSend: Bool {
        switch self {
        case .pending, .uploading: return true
        case .done, .error: return false
        }
    }

    public var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

public struct AttachmentDraft: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var totalBytes: Int
    public var data: Data
    public var state: AttachmentChipState

    public init(
        id: UUID = UUID(),
        name: String,
        data: Data,
        state: AttachmentChipState = .pending
    ) {
        self.id = id
        self.name = name
        self.totalBytes = data.count
        self.data = data
        self.state = state
    }

    public var sizeLabel: String {
        AttachmentFormatting.byteCount(totalBytes)
    }

    public var displayLabel: String {
        "\(name) · \(sizeLabel)"
    }
}

public enum AttachmentFormatting {
    public static func byteCount(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }
}

public enum AttachmentPromptPrefix {
    /// Builds the block prepended to the user prompt once host paths are known.
    public static func make(hostPaths: [String]) -> String {
        guard !hostPaths.isEmpty else { return "" }
        var lines = ["Attached files (read from disk):"]
        for path in hostPaths {
            lines.append("- \(path)")
        }
        lines.append("")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    public static func apply(userPrompt: String, hostPaths: [String]) -> String {
        let prefix = make(hostPaths: hostPaths)
        if prefix.isEmpty { return userPrompt }
        return prefix + userPrompt
    }
}

public enum AttachmentChunking {
    /// Splits `data` into ≤`maxChunkBytes` slices for sequential `attachment.put` RPCs.
    public static func chunks(
        of data: Data,
        maxChunkBytes: Int = AttachmentLimits.maxChunkBytes
    ) -> [Data] {
        precondition(maxChunkBytes > 0)
        guard !data.isEmpty else { return [Data()] }
        var result: [Data] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + maxChunkBytes, data.count)
            result.append(data.subdata(in: offset..<end))
            offset = end
        }
        return result
    }

    public static func chunkCount(
        byteCount: Int,
        maxChunkBytes: Int = AttachmentLimits.maxChunkBytes
    ) -> Int {
        guard byteCount > 0 else { return 1 }
        return (byteCount + maxChunkBytes - 1) / maxChunkBytes
    }
}

public enum AttachmentDraftStore {
    /// Appends drafts up to the 5-file / 20MB caps. Oversized or overflow items are skipped.
    public static func appending(
        _ existing: [AttachmentDraft],
        newItems: [AttachmentDraft]
    ) -> [AttachmentDraft] {
        var result = existing
        for item in newItems {
            guard result.count < AttachmentLimits.maxFiles else { break }
            guard item.totalBytes > 0, item.totalBytes <= AttachmentLimits.maxBytesPerFile else { continue }
            result.append(item)
        }
        return result
    }

    public static func canSend(_ drafts: [AttachmentDraft]) -> Bool {
        guard !drafts.isEmpty else { return true }
        if drafts.contains(where: { $0.state.isError }) { return false }
        if drafts.contains(where: { $0.state.blocksSend }) { return false }
        return drafts.allSatisfy(\.state.isReadyToSend)
    }

    public static func hostPaths(_ drafts: [AttachmentDraft]) -> [String] {
        drafts.compactMap {
            if case .done(let path) = $0.state { return path }
            return nil
        }
    }

    public static func withState(
        _ drafts: [AttachmentDraft],
        id: UUID,
        state: AttachmentChipState
    ) -> [AttachmentDraft] {
        drafts.map { draft in
            guard draft.id == id else { return draft }
            var copy = draft
            copy.state = state
            return copy
        }
    }
}

/// Uploads one attachment via chunked `attachment.put`. `sendChunk` is transport-specific.
public enum AttachmentUploader {
    public struct ChunkParams: Sendable {
        public let conversationId: String?
        public let name: String
        public let totalBytes: Int
        public let seq: Int
        public let dataBase64: String
        public let done: Bool
    }

    public struct ChunkResult: Sendable {
        public let path: String?
        public let error: String?

        public init(path: String?, error: String?) {
            self.path = path
            self.error = error
        }
    }

    @MainActor
    public static func upload(
        draft: AttachmentDraft,
        conversationId: String?,
        sendChunk: (ChunkParams) async throws -> ChunkResult,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> String {
        let parts = AttachmentChunking.chunks(of: draft.data)
        var hostPath: String?
        for (seq, part) in parts.enumerated() {
            let done = seq == parts.count - 1
            let result = try await sendChunk(
                ChunkParams(
                    conversationId: conversationId,
                    name: draft.name,
                    totalBytes: draft.totalBytes,
                    seq: seq,
                    dataBase64: part.base64EncodedString(),
                    done: done
                )
            )
            if let err = result.error, !err.isEmpty {
                throw AttachmentUploadError.host(err)
            }
            if done {
                guard let path = result.path, !path.isEmpty else {
                    throw AttachmentUploadError.missingPath
                }
                hostPath = path
            }
            onProgress?(Double(seq + 1) / Double(parts.count))
        }
        guard let hostPath else { throw AttachmentUploadError.missingPath }
        return hostPath
    }
}

public enum AttachmentUploadError: Error, LocalizedError, Equatable {
    case missingPath
    case host(String)
    case noTransport

    public var errorDescription: String? {
        switch self {
        case .missingPath: return "Upload finished without a host path"
        case .host(let message): return message
        case .noTransport: return "No connected machine to upload attachments"
        }
    }
}
