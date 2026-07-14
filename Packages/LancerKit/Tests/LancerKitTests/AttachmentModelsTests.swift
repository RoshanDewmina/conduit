import Testing
import Foundation
@testable import AppFeature
import LancerCore

private let sampleDigest = String(repeating: "ab", count: 32)

@Suite struct AttachmentModelsTests {
    @Test("chip state machine: pending → uploading → done")
    func chipHappyPath() {
        var draft = AttachmentDraft(name: "a.png", data: Data([1, 2, 3]))
        #expect(draft.state == .pending)
        #expect(draft.state.blocksSend)
        #expect(!draft.state.isReadyToSend)

        draft.state = .uploading(progress: 0.5)
        #expect(draft.state.blocksSend)
        #expect(!draft.state.isReadyToSend)

        let receipt = AttachmentUploadReceipt(
            id: "srv-1", path: "/tmp/a.png", contentDigest: sampleDigest
        )
        draft.state = .done(receipt)
        #expect(!draft.state.blocksSend)
        #expect(draft.state.isReadyToSend)
        #expect(AttachmentDraftStore.canSend([draft]))
        #expect(AttachmentDraftStore.hostPaths([draft]) == ["/tmp/a.png"])
    }

    @Test("chip error blocks send until removed")
    func chipErrorBlocksSend() {
        let draft = AttachmentDraft(
            name: "b.pdf",
            data: Data([9]),
            state: .error(message: "upload failed")
        )
        #expect(draft.state.isError)
        #expect(!AttachmentDraftStore.canSend([draft]))
        #expect(AttachmentDraftStore.canSend([]))
    }

    @Test("chunking math respects 256KB cap")
    func chunkingMath() {
        #expect(AttachmentChunking.chunkCount(byteCount: 0) == 1)
        #expect(AttachmentChunking.chunkCount(byteCount: 1) == 1)
        #expect(AttachmentChunking.chunkCount(byteCount: AttachmentLimits.maxChunkBytes) == 1)
        #expect(AttachmentChunking.chunkCount(byteCount: AttachmentLimits.maxChunkBytes + 1) == 2)
        #expect(AttachmentChunking.chunkCount(byteCount: AttachmentLimits.maxChunkBytes * 3) == 3)

        let data = Data(repeating: 7, count: AttachmentLimits.maxChunkBytes + 10)
        let parts = AttachmentChunking.chunks(of: data)
        #expect(parts.count == 2)
        #expect(parts[0].count == AttachmentLimits.maxChunkBytes)
        #expect(parts[1].count == 10)
        #expect(parts.reduce(0) { $0 + $1.count } == data.count)
    }

    @Test("appending enforces 5-file and 20MB caps")
    func appendingCaps() {
        let existing = (0..<AttachmentLimits.maxFiles).map {
            AttachmentDraft(name: "f\($0).txt", data: Data([1]))
        }
        let overflow = AttachmentDraftStore.appending(
            existing,
            newItems: [AttachmentDraft(name: "extra.txt", data: Data([2]))]
        )
        #expect(overflow.count == AttachmentLimits.maxFiles)

        let oversized = Data(repeating: 1, count: AttachmentLimits.maxBytesPerFile + 1)
        let skipped = AttachmentDraftStore.appending(
            [],
            newItems: [AttachmentDraft(name: "huge.bin", data: oversized)]
        )
        #expect(skipped.isEmpty)
    }

    @Test("draft reference uses server id/path/digest and keeps previewCacheKey as draft UUID")
    func draftReferenceUsesServerReceipt() {
        let image = AttachmentDraft(name: "photo.jpg", data: Data([1, 2, 3]), mimeType: "image/jpeg")
        let file = AttachmentDraft(name: "notes.txt", data: Data([4]), mimeType: "text/plain")
        let imageRef = image.reference(
            id: "srv-image",
            hostPath: "/Users/me/.lancer/attachments/objects/\(sampleDigest)",
            contentDigest: sampleDigest
        )
        let fileDigest = String(repeating: "cd", count: 32)
        let fileRef = file.reference(
            id: "srv-file",
            hostPath: "/Users/me/.lancer/attachments/objects/\(fileDigest)",
            contentDigest: fileDigest
        )
        #expect(imageRef.kind == .image)
        #expect(imageRef.id == "srv-image")
        #expect(imageRef.id != image.id.uuidString)
        #expect(imageRef.previewCacheKey == image.id.uuidString)
        #expect(imageRef.contentDigest == sampleDigest)
        #expect(fileRef.kind == .file)
        #expect(fileRef.id == "srv-file")
        #expect(AttachmentContentDigest.isValid(sampleDigest))
        #expect(!AttachmentContentDigest.isValid("not-a-digest"))
        #expect(!AttachmentContentDigest.isValid(String(repeating: "A", count: 64)))

        let ready = [
            AttachmentDraftStore.withState(
                [image], id: image.id,
                state: .done(AttachmentUploadReceipt(
                    id: "srv-image",
                    path: "/Users/me/.lancer/attachments/objects/\(sampleDigest)",
                    contentDigest: sampleDigest
                ))
            )[0],
            AttachmentDraftStore.withState(
                [file], id: file.id,
                state: .done(AttachmentUploadReceipt(
                    id: "srv-file",
                    path: "/Users/me/.lancer/attachments/objects/\(fileDigest)",
                    contentDigest: fileDigest
                ))
            )[0],
        ]
        let refs = AttachmentDraftStore.references(from: ready)
        #expect(refs.count == 2)
        #expect(refs[0].id == "srv-image")
        #expect(refs[0].contentDigest == sampleDigest)
        #expect(refs[0].previewCacheKey == image.id.uuidString)
    }

    @Test("uploader requires server id/path/digest on final chunk")
    @MainActor
    func uploaderRequiresFinalReceipt() async throws {
        let draft = AttachmentDraft(name: "a.bin", data: Data([1, 2, 3, 4]))
        let receipt = try await AttachmentUploader.upload(
            draft: draft,
            conversationId: nil,
            sendChunk: { params in
                #expect(params.done)
                return AttachmentUploader.ChunkResult(
                    id: "srv-a",
                    path: "/host/objects/\(sampleDigest)",
                    contentDigest: sampleDigest,
                    error: nil
                )
            }
        )
        #expect(receipt.id == "srv-a")
        #expect(receipt.contentDigest == sampleDigest)

        await #expect(throws: AttachmentUploadError.missingReceiptFields) {
            _ = try await AttachmentUploader.upload(
                draft: draft,
                conversationId: nil,
                sendChunk: { _ in
                    AttachmentUploader.ChunkResult(path: "/only-path", error: nil)
                }
            )
        }

        await #expect(throws: AttachmentUploadError.invalidContentDigest) {
            _ = try await AttachmentUploader.upload(
                draft: draft,
                conversationId: nil,
                sendChunk: { _ in
                    AttachmentUploader.ChunkResult(
                        id: "srv",
                        path: "/p",
                        contentDigest: "NOTHEX",
                        error: nil
                    )
                }
            )
        }
    }

    @Test("error retry policy preserves initial attachments when lastAttempt is nil")
    func errorRetryPreservesInitialAttachments() {
        let refs = [
            ConversationAttachmentReference(
                id: "a1", name: "photo.jpg", mimeType: "image/jpeg",
                byteCount: 10, kind: .image,
                hostPath: "/host/a", previewCacheKey: "draft-1",
                contentDigest: sampleDigest
            )
        ]
        let policy = LiveThreadErrorRetryPolicy.resolve(
            hasLastAttempt: false,
            shouldSendInitialPrompt: true,
            initialAttachments: refs
        )
        #expect(policy == .sendInitial(attachments: refs))
        if case .sendInitial(let attachments) = policy {
            #expect(attachments == refs)
            #expect(attachments.first?.contentDigest == sampleDigest)
        }
        #expect(
            LiveThreadErrorRetryPolicy.resolve(
                hasLastAttempt: true,
                shouldSendInitialPrompt: true,
                initialAttachments: refs
            ) == .retryLastAttempt
        )
    }

    @Test("attachment layout is adaptive")
    func attachmentLayoutIsAdaptive() {
        #expect(AttachmentLayoutPolicy.columns(for: 1) == 1)
        #expect(AttachmentLayoutPolicy.columns(for: 2) == 2)
        #expect(AttachmentLayoutPolicy.columns(for: 5) == 2)
        #expect(AttachmentLayoutPolicy.columns(for: 0) == 0)
    }

    @Test("legacy attachment prefix is hidden from display")
    func legacyAttachmentPrefixIsHiddenFromDisplay() {
        let prompt = "Attached files (read from disk):\n- /Users/me/.lancer/attachments/photo.jpg\n\nDescribe it"
        #expect(AttachmentDisplayText.cleanPrompt(prompt) == "Describe it")
        #expect(AttachmentDisplayText.cleanPrompt("plain hello") == "plain hello")
        #expect(!AttachmentDisplayText.cleanPrompt(prompt).contains("/Users/"))
        #expect(!AttachmentDisplayText.cleanPrompt(prompt).contains(".lancer/attachments"))
    }

    @Test("presentation model never surfaces host paths or malformed URL names")
    func presentationOmitsHostPaths() {
        let ref = ConversationAttachmentReference(
            id: "a1", name: "https://evil.example/photo.jpg", mimeType: "image/jpeg",
            byteCount: 310_992, kind: .image,
            hostPath: "/Users/me/.lancer/attachments/photo.jpg",
            previewCacheKey: "a1",
            contentDigest: sampleDigest
        )
        let presented = AttachmentPresentation.card(for: ref, previewAvailable: true)
        #expect(!presented.accessibilityLabel.contains("/Users/"))
        #expect(!presented.accessibilityLabel.contains(ref.hostPath))
        #expect(!presented.accessibilityLabel.contains("https://"))
        #expect(!presented.shareCopy.contains("/Users/"))
        #expect(!presented.shareCopy.contains("://"))
        #expect(presented.displayName == "photo.jpg")
    }

    @Test("preview cache survives recreation and rejects traversal")
    func previewCacheSurvivesRecreation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lancer-preview-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try AttachmentPreviewCache(directory: directory).storePreview(Data("preview".utf8), for: "a1")
        #expect(try AttachmentPreviewCache(directory: directory).previewData(for: "a1") == Data("preview".utf8))

        #expect(throws: AttachmentPreviewCacheError.self) {
            try AttachmentPreviewCache(directory: directory).storePreview(Data("x".utf8), for: "../escape")
        }
        #expect(throws: AttachmentPreviewCacheError.self) {
            try AttachmentPreviewCache(directory: directory).storePreview(Data("x".utf8), for: "a/../../b")
        }
        #expect(try AttachmentPreviewCache(directory: directory).previewData(for: "missing") == nil)
    }

    @Test("preview cache rejects oversized entries before write")
    func previewCacheRejectsOversizedEntry() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lancer-preview-cache-big-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try AttachmentPreviewCache(
            directory: directory,
            maxBytesPerEntry: 8
        )
        #expect(throws: AttachmentPreviewCacheError.entryTooLarge) {
            try cache.storePreview(Data(repeating: 1, count: 16), for: "big")
        }
        #expect(try cache.previewData(for: "big") == nil)
    }

    @Test("preview cache evicts corrupt entries and respects caps")
    func previewCacheEvictsCorruptAndCaps() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lancer-preview-cache-cap-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = try AttachmentPreviewCache(
            directory: directory,
            maxEntries: 2,
            maxTotalBytes: 32,
            maxAge: 3600
        )
        try cache.storePreview(Data(repeating: 1, count: 10), for: "a")
        try cache.storePreview(Data(repeating: 2, count: 10), for: "b")
        try cache.storePreview(Data(repeating: 3, count: 10), for: "c")
        #expect(try cache.previewData(for: "a") == nil)
        #expect(try cache.previewData(for: "b") == Data(repeating: 2, count: 10))
        #expect(try cache.previewData(for: "c") == Data(repeating: 3, count: 10))

        let key = "corrupt"
        let validPath = try cache.fileURL(for: key)
        try Data().write(to: validPath)
        #expect(try cache.previewData(for: key) == nil)
        #expect(!FileManager.default.fileExists(atPath: validPath.path))
    }

    @Test("makePreviewData rejects oversized input")
    func makePreviewDataRejectsOversizedInput() {
        let huge = Data(repeating: 0xFF, count: AttachmentPreviewCache.defaultMaxInputBytes + 1)
        #expect(AttachmentPreviewCache.makePreviewData(from: huge, mimeType: "image/jpeg") == nil)
    }

    @Test("append request builder keeps prompt clean and carries refs")
    func appendRequestKeepsPromptClean() {
        let refs = [
            ConversationAttachmentReference(
                id: "a1", name: "photo.jpg", mimeType: "image/jpeg",
                byteCount: 100, kind: .image,
                hostPath: "/Users/me/.lancer/attachments/photo.jpg",
                previewCacheKey: "a1",
                contentDigest: sampleDigest
            )
        ]
        let request = AttachmentSendPipeline.appendRequest(
            prompt: "Describe this image",
            clientTurnId: "ios:1",
            attachments: refs
        )
        #expect(request.prompt == "Describe this image")
        #expect(!request.prompt.contains("/Users/"))
        #expect(!request.prompt.contains("Attached files"))
        #expect(request.attachments == refs)
        #expect(request.attachments?.first?.contentDigest == sampleDigest)
        #expect(request.clientTurnId == "ios:1")

        let retried = AttachmentSendPipeline.retryPreserving(
            request,
            baseSeq: 9
        )
        #expect(retried.clientTurnId == "ios:1")
        #expect(retried.attachments == refs)
        #expect(retried.baseSeq == 9)
        #expect(retried.prompt == "Describe this image")
    }
}
