import Foundation
import LancerCore

/// Pure attachment draft + upload helpers for the Context sheet / composer.
/// OS-agnostic so `swift test` can drive the chip state machine, chunking, and
/// send pipeline without UIKit.

public enum AttachmentLimits {
    public static let maxFiles = 5
    public static let maxBytesPerFile = 20 * 1024 * 1024
    /// Pre-encryption chunk size for `attachment.put` (E2E + SSH).
    public static let maxChunkBytes = 256 * 1024
}

/// Server-issued identity from a finalized `attachment.put`.
public struct AttachmentUploadReceipt: Equatable, Sendable {
    public let id: String
    public let path: String
    public let contentDigest: String

    public init(id: String, path: String, contentDigest: String) {
        self.id = id
        self.path = path
        self.contentDigest = contentDigest
    }
}

public enum AttachmentChipState: Equatable, Sendable {
    case pending
    case uploading(progress: Double)
    case done(AttachmentUploadReceipt)
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
    public var mimeType: String?

    public init(
        id: UUID = UUID(),
        name: String,
        data: Data,
        state: AttachmentChipState = .pending,
        mimeType: String? = nil
    ) {
        self.id = id
        self.name = name
        self.totalBytes = data.count
        self.data = data
        self.state = state
        self.mimeType = mimeType
    }

    public var sizeLabel: String {
        AttachmentFormatting.byteCount(totalBytes)
    }

    public var displayLabel: String {
        "\(name) · \(sizeLabel)"
    }

    /// Builds a transport reference from a server-issued put receipt.
    /// `previewCacheKey` stays the client draft UUID so local preview cache
    /// remains stable across upload.
    public func reference(
        id: String,
        hostPath: String,
        contentDigest: String,
        mimeType: String? = nil
    ) -> ConversationAttachmentReference {
        let resolvedMime = mimeType ?? self.mimeType
        let kind: ConversationAttachmentReference.Kind =
            resolvedMime?.hasPrefix("image/") == true ? .image : .file
        return ConversationAttachmentReference(
            id: id,
            name: name,
            mimeType: resolvedMime,
            byteCount: totalBytes,
            kind: kind,
            hostPath: hostPath,
            previewCacheKey: self.id.uuidString,
            contentDigest: contentDigest
        )
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
            if case .done(let receipt) = $0.state { return receipt.path }
            return nil
        }
    }

    public static func references(from drafts: [AttachmentDraft]) -> [ConversationAttachmentReference] {
        drafts.compactMap { draft in
            guard case .done(let receipt) = draft.state else { return nil }
            return draft.reference(
                id: receipt.id,
                hostPath: receipt.path,
                contentDigest: receipt.contentDigest
            )
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

/// Adaptive grid columns for image attachments in a sent bubble.
public enum AttachmentLayoutPolicy {
    public static func columns(for count: Int) -> Int {
        switch count {
        case ...0: return 0
        case 1: return 1
        default: return 2
        }
    }
}

/// Strips the legacy host-path prompt prefix from historical turns.
public enum AttachmentDisplayText {
    public static let legacyPrefixMarker = "Attached files (read from disk):"

    public static func cleanPrompt(_ prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(legacyPrefixMarker) else { return trimmed }
        // Split on the blank line that separates the path list from user text.
        let parts = trimmed.components(separatedBy: "\n\n")
        guard parts.count >= 2 else {
            // Path-only legacy prompt — hide paths entirely.
            return ""
        }
        return parts.dropFirst().joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Filenames parsed from a legacy prefix for clean file-card fallbacks.
    public static func legacyFilenames(in prompt: String) -> [String] {
        guard prompt.contains(legacyPrefixMarker) else { return [] }
        return prompt
            .split(separator: "\n")
            .compactMap { line -> String? in
                let raw = line.trimmingCharacters(in: .whitespaces)
                guard raw.hasPrefix("- ") else { return nil }
                let path = String(raw.dropFirst(2))
                return URL(fileURLWithPath: path).lastPathComponent
            }
            .filter { !$0.isEmpty }
    }
}

/// User-facing presentation for one attachment — never includes `hostPath`.
public struct AttachmentPresentation: Equatable, Sendable {
    public let displayName: String
    public let accessibilityLabel: String
    public let shareCopy: String
    public let kind: ConversationAttachmentReference.Kind
    public let sizeLabel: String
    public let previewAvailable: Bool

    public static func card(
        for ref: ConversationAttachmentReference,
        previewAvailable: Bool
    ) -> AttachmentPresentation {
        let safeName = sanitizedDisplayName(ref.name)
        let size = AttachmentFormatting.byteCount(ref.byteCount)
        let kindWord = ref.kind == .image ? "Attached image" : "Attached file"
        return AttachmentPresentation(
            displayName: safeName,
            accessibilityLabel: "\(kindWord), \(safeName), \(size)",
            shareCopy: "\(safeName) (\(size))",
            kind: ref.kind,
            sizeLabel: size,
            previewAvailable: previewAvailable
        )
    }

    /// Strips path/URL characters so MIME/name cannot drive arbitrary opens.
    public static func sanitizedDisplayName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "attachment" }
        let base = (trimmed as NSString).lastPathComponent
        let cleaned = base
            .replacingOccurrences(of: "://", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        return cleaned.isEmpty ? "attachment" : cleaned
    }
}

/// Builds clean-prompt append requests for the composer / sync coordinator.
public enum AttachmentSendPipeline {
    public static func appendRequest(
        prompt: String,
        clientTurnId: String,
        attachments: [ConversationAttachmentReference],
        conversationId: String? = nil,
        baseSeq: Int = 0,
        agent: String? = nil,
        cwd: String? = nil,
        model: String? = nil,
        budgetUSD: Double? = nil,
        useWorktree: Bool? = nil,
        contract: ProofReceipt.Contract? = nil
    ) -> ConversationAppendRequest {
        ConversationAppendRequest(
            conversationId: conversationId,
            baseSeq: baseSeq,
            clientTurnId: clientTurnId,
            agent: agent,
            cwd: cwd,
            prompt: prompt,
            model: model,
            budgetUSD: budgetUSD,
            useWorktree: useWorktree,
            contract: contract,
            attachments: attachments.isEmpty ? nil : attachments
        )
    }

    public static func retryPreserving(
        _ request: ConversationAppendRequest,
        baseSeq: Int
    ) -> ConversationAppendRequest {
        ConversationAppendRequest(
            conversationId: request.conversationId,
            baseSeq: baseSeq,
            clientTurnId: request.clientTurnId,
            agent: request.agent,
            cwd: request.cwd,
            prompt: request.prompt,
            model: request.model,
            budgetUSD: request.budgetUSD,
            useWorktree: request.useWorktree,
            contract: request.contract,
            attachments: request.attachments,
            fullTools: request.fullTools
        )
    }
}

/// Pure retry routing for the live-thread error card (testable without SwiftUI).
public enum LiveThreadErrorRetryPolicy: Equatable, Sendable {
    case retryLastAttempt
    case sendInitial(attachments: [ConversationAttachmentReference])
    case adoptObserved

    public static func resolve(
        hasLastAttempt: Bool,
        shouldSendInitialPrompt: Bool,
        initialAttachments: [ConversationAttachmentReference]
    ) -> LiveThreadErrorRetryPolicy {
        if hasLastAttempt { return .retryLastAttempt }
        if shouldSendInitialPrompt {
            return .sendInitial(attachments: initialAttachments)
        }
        return .adoptObserved
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
        public let id: String?
        public let path: String?
        public let contentDigest: String?
        public let error: String?

        public init(
            id: String? = nil,
            path: String?,
            contentDigest: String? = nil,
            error: String?
        ) {
            self.id = id
            self.path = path
            self.contentDigest = contentDigest
            self.error = error
        }
    }

    @MainActor
    public static func upload(
        draft: AttachmentDraft,
        conversationId: String?,
        sendChunk: (ChunkParams) async throws -> ChunkResult,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> AttachmentUploadReceipt {
        let parts = AttachmentChunking.chunks(of: draft.data)
        var receipt: AttachmentUploadReceipt?
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
                guard let id = result.id, !id.isEmpty,
                      let path = result.path, !path.isEmpty,
                      let digest = result.contentDigest, !digest.isEmpty
                else {
                    throw AttachmentUploadError.missingReceiptFields
                }
                guard AttachmentContentDigest.isValid(digest) else {
                    throw AttachmentUploadError.invalidContentDigest
                }
                receipt = AttachmentUploadReceipt(id: id, path: path, contentDigest: digest)
            }
            onProgress?(Double(seq + 1) / Double(parts.count))
        }
        guard let receipt else { throw AttachmentUploadError.missingReceiptFields }
        return receipt
    }
}

public enum AttachmentUploadError: Error, LocalizedError, Equatable {
    case missingReceiptFields
    case invalidContentDigest
    case host(String)
    case noTransport

    public var errorDescription: String? {
        switch self {
        case .missingReceiptFields:
            return "Upload finished without a server id, path, and content digest"
        case .invalidContentDigest:
            return "Upload returned an invalid content digest"
        case .host(let message): return message
        case .noTransport: return "No connected machine to upload attachments"
        }
    }
}
