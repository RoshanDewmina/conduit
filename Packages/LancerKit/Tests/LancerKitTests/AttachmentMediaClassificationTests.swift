import Testing
import Foundation
@testable import AppFeature
import LancerCore

@Suite struct AttachmentMediaClassificationTests {
    @Test("mime image/* and common extensions classify as image")
    func imagesByMimeAndExtension() {
        #expect(AttachmentMediaClassification.classify(mimeType: "image/png", fileName: "x.bin") == .image)
        #expect(AttachmentMediaClassification.classify(mimeType: "image/jpeg", fileName: "x") == .image)
        #expect(AttachmentMediaClassification.classify(mimeType: "image/heic", fileName: "x") == .image)
        #expect(AttachmentMediaClassification.classify(mimeType: "image/gif", fileName: "x") == .image)
        #expect(AttachmentMediaClassification.classify(mimeType: nil, fileName: "shot.PNG") == .image)
        #expect(AttachmentMediaClassification.classify(mimeType: nil, fileName: "a.jpg") == .image)
        #expect(AttachmentMediaClassification.classify(mimeType: nil, fileName: "a.jpeg") == .image)
        #expect(AttachmentMediaClassification.classify(mimeType: nil, fileName: "a.heic") == .image)
        #expect(AttachmentMediaClassification.classify(mimeType: nil, fileName: "a.gif") == .image)
        #expect(AttachmentMediaClassification.classify(mimeType: "", fileName: "a.webp") == .image)
    }

    @Test("mime video/* and mov/mp4/m4v classify as video")
    func videosByMimeAndExtension() {
        #expect(AttachmentMediaClassification.classify(mimeType: "video/mp4", fileName: "x.bin") == .video)
        #expect(AttachmentMediaClassification.classify(mimeType: "video/quicktime", fileName: "x") == .video)
        #expect(AttachmentMediaClassification.classify(mimeType: nil, fileName: "clip.mov") == .video)
        #expect(AttachmentMediaClassification.classify(mimeType: nil, fileName: "clip.MP4") == .video)
        #expect(AttachmentMediaClassification.classify(mimeType: nil, fileName: "clip.m4v") == .video)
    }

    @Test("non-media stays file")
    func nonMediaIsFile() {
        #expect(AttachmentMediaClassification.classify(mimeType: "application/pdf", fileName: "a.pdf") == .file)
        #expect(AttachmentMediaClassification.classify(mimeType: "text/plain", fileName: "a.txt") == .file)
        #expect(AttachmentMediaClassification.classify(mimeType: nil, fileName: "notes.md") == .file)
        #expect(AttachmentMediaClassification.classify(mimeType: nil, fileName: "noext") == .file)
    }

    @Test("reference classifier prefers mime then wire kind image fallback")
    func referenceClassifier() {
        let digest = String(repeating: "ab", count: 32)
        let pngFileKind = ConversationAttachmentReference(
            id: "1", name: "shot.png", mimeType: "image/png",
            byteCount: 10, kind: .file,
            hostPath: "/host/a", previewCacheKey: "k1", contentDigest: digest
        )
        #expect(AttachmentMediaClassification.classify(reference: pngFileKind) == .image)
        #expect(AttachmentMediaClassification.classify(reference: pngFileKind).isInlineMedia)

        let legacyImage = ConversationAttachmentReference(
            id: "2", name: "mystery", mimeType: nil,
            byteCount: 10, kind: .image,
            hostPath: "/host/b", previewCacheKey: "k2", contentDigest: digest
        )
        #expect(AttachmentMediaClassification.classify(reference: legacyImage) == .image)

        let video = ConversationAttachmentReference(
            id: "3", name: "clip.mov", mimeType: "video/quicktime",
            byteCount: 100, kind: .file,
            hostPath: "/host/c", previewCacheKey: "k3", contentDigest: digest
        )
        #expect(AttachmentMediaClassification.classify(reference: video) == .video)
        #expect(AttachmentMediaClassification.classify(reference: video).isInlineMedia)

        let pdf = ConversationAttachmentReference(
            id: "4", name: "doc.pdf", mimeType: "application/pdf",
            byteCount: 10, kind: .file,
            hostPath: "/host/d", previewCacheKey: "k4", contentDigest: digest
        )
        #expect(AttachmentMediaClassification.classify(reference: pdf) == .file)
        #expect(!AttachmentMediaClassification.classify(reference: pdf).isInlineMedia)
    }

    @Test("draft reference maps video mime to wire kind file and image mime to image")
    func draftReferenceWireKind() {
        let digest = String(repeating: "cd", count: 32)
        let image = AttachmentDraft(name: "a.png", data: Data([1]), mimeType: "image/png")
        let video = AttachmentDraft(name: "b.mov", data: Data([2]), mimeType: "video/quicktime")
        let imageRef = image.reference(id: "i", hostPath: "/p/i", contentDigest: digest)
        let videoRef = video.reference(id: "v", hostPath: "/p/v", contentDigest: digest)
        #expect(imageRef.kind == .image)
        #expect(videoRef.kind == .file)
        #expect(AttachmentMediaClassification.classify(reference: videoRef) == .video)
    }
}
