import Testing
import Foundation
@testable import AppFeature

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

        draft.state = .done(hostPath: "/tmp/a.png")
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

    @Test("prompt prefix format")
    func promptPrefix() {
        let prefix = AttachmentPromptPrefix.make(hostPaths: [
            "/Users/me/.lancer/attachments/2026-07-12/uuid-a.png",
            "/Users/me/.lancer/attachments/2026-07-12/uuid-b.pdf",
        ])
        #expect(prefix.hasPrefix("Attached files (read from disk):\n"))
        #expect(prefix.contains("- /Users/me/.lancer/attachments/2026-07-12/uuid-a.png\n"))
        #expect(prefix.contains("- /Users/me/.lancer/attachments/2026-07-12/uuid-b.pdf\n"))
        #expect(prefix.hasSuffix("\n\n"))

        let applied = AttachmentPromptPrefix.apply(
            userPrompt: "please review",
            hostPaths: ["/tmp/x.png"]
        )
        #expect(applied == "Attached files (read from disk):\n- /tmp/x.png\n\nplease review")
        #expect(AttachmentPromptPrefix.apply(userPrompt: "hi", hostPaths: []) == "hi")
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
}
