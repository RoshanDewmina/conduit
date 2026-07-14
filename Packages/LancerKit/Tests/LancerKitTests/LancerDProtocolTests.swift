import Testing
import Foundation
@testable import LancerCore

// MARK: - Golden JSON helpers (Go 7df8b831 wire contract)

private enum ConversationAttachmentGoldenFixtures {
    /// Go `json.Marshal(sampleImageAttachment())` — all fields including mimeType.
    static let attachmentImageWithMimeType = """
    {"id":"a1","name":"photo.jpg","mimeType":"image/jpeg","byteCount":310992,"kind":"image","hostPath":"/Users/me/.lancer/attachments/photo.jpg","previewCacheKey":"a1"}
    """

    /// Go `json.Marshal(sampleFileAttachment())` — mimeType omitted via `,omitempty`.
    static let attachmentFileWithoutMimeType = """
    {"id":"a2","name":"notes.txt","byteCount":42,"kind":"file","hostPath":"/Users/me/.lancer/attachments/notes.txt","previewCacheKey":"a2"}
    """

    /// New-chat append with one image attachment.
    static let appendNewChatWithAttachments = """
    {"baseSeq":0,"clientTurnId":"ios-device-uuid:1","agent":"claudeCode","cwd":"~","prompt":"Describe this image","model":"sonnet","budgetUSD":5,"attachments":[{"id":"a1","name":"photo.jpg","mimeType":"image/jpeg","byteCount":310992,"kind":"image","hostPath":"/Users/me/.lancer/attachments/photo.jpg","previewCacheKey":"a1"}]}
    """

    /// Follow-up append with one image attachment.
    static let appendFollowUpWithAttachments = """
    {"conversationId":"conv_1","baseSeq":42,"clientTurnId":"ios-device-uuid:2","prompt":"Now add a regression test","attachments":[{"id":"a1","name":"photo.jpg","mimeType":"image/jpeg","byteCount":310992,"kind":"image","hostPath":"/Users/me/.lancer/attachments/photo.jpg","previewCacheKey":"a1"}]}
    """

    /// Pre-attachment new-chat append — proves custom Codable preserves legacy wire shape.
    static let appendLegacyNewChatWithoutAttachments = """
    {"baseSeq":0,"clientTurnId":"ios-device-uuid:1","agent":"claudeCode","cwd":"~","prompt":"Fix the failing auth test","model":"sonnet","budgetUSD":5}
    """

    /// Turn envelope with one attachment.
    static let turnWithAttachments = """
    {"id":"t1","conversationId":"c1","ordinal":1,"clientTurnId":"ct1","prompt":"Summarize","runId":"r1","provider":"claudeCode","status":"completed","startedAt":"2026-07-14T00:00:00Z","attachments":[{"id":"a1","name":"photo.jpg","mimeType":"image/jpeg","byteCount":310992,"kind":"image","hostPath":"/Users/me/.lancer/attachments/photo.jpg","previewCacheKey":"a1"}]}
    """

    /// Legacy turn without attachments — all pre-attachment optional fields present.
    static let turnLegacyWithoutAttachments = """
    {"id":"turn_1","conversationId":"conv_1","ordinal":2,"clientTurnId":"ios-uuid:2","prompt":"Now add a regression test","runId":"run_2","provider":"claudeCode","vendorSessionId":"sess_abc","status":"failed","startedAt":"2026-07-03T01:00:00Z","completedAt":"2026-07-03T01:05:00Z","errorMessage":"exit code 1"}
    """

    /// Default turn with empty attachments slice — attachments key must be absent.
    static let turnDefaultEmptyAttachments = """
    {"id":"t1","conversationId":"c1","ordinal":1,"clientTurnId":"ct1","prompt":"hello","runId":"r1","provider":"claudeCode","status":"completed","startedAt":"2026-07-14T00:00:00Z"}
    """
}

private func goldenJSONObject(_ json: String) throws -> Any {
    try JSONSerialization.jsonObject(with: Data(json.utf8))
}

private func encodedJSONObject<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
}

/// Canonical JSON object equality — key order independent.
private func jsonObjectsEqual(_ lhs: Any, _ rhs: Any) -> Bool {
    switch (lhs, rhs) {
    case let (l as [String: Any], r as [String: Any]):
        guard l.keys.count == r.keys.count else { return false }
        for (key, lVal) in l {
            guard let rVal = r[key], jsonObjectsEqual(lVal, rVal) else { return false }
        }
        return true
    case let (l as [Any], r as [Any]):
        guard l.count == r.count else { return false }
        for (lElem, rElem) in zip(l, r) where !jsonObjectsEqual(lElem, rElem) { return false }
        return true
    case let (l as NSNumber, r as NSNumber):
        return l.isEqual(to: r)
    case let (l as String, r as String):
        return l == r
    case let (l as Bool, r as Bool):
        return l == r
    case is (NSNull, NSNull):
        return true
    default:
        return false
    }
}

private let sampleImageAttachment = ConversationAttachmentReference(
    id: "a1", name: "photo.jpg", mimeType: "image/jpeg",
    byteCount: 310_992, kind: .image,
    hostPath: "/Users/me/.lancer/attachments/photo.jpg",
    previewCacheKey: "a1"
)

private let sampleFileAttachmentNoMime = ConversationAttachmentReference(
    id: "a2", name: "notes.txt", mimeType: nil,
    byteCount: 42, kind: .file,
    hostPath: "/Users/me/.lancer/attachments/notes.txt",
    previewCacheKey: "a2"
)

@Suite("LancerDProtocol")
struct LancerDProtocolTests {
    @Test("approval pending round-trip decode")
    func approvalPendingDecode() throws {
        let json = """
        {"jsonrpc":"2.0","method":"agent.approval.pending","params":{"id":"00000000-0000-0000-0000-000000000001","agent":"claudeCode","kind":"command","command":"rm -rf /","cwd":"/home/user","risk":3}}
        """.data(using: .utf8)!
        let event = DaemonEvent.decode(from: json)
        if case .approvalPending(let p) = event {
            #expect(p.command == "rm -rf /")
            #expect(p.risk == 3)
            #expect(p.approvalRisk == .critical)
        } else {
            Issue.record("Expected .approvalPending")
        }
    }

    @Test("approval pending decode carries the daemon's contentHash")
    func approvalPendingDecodeContentHash() throws {
        let json = """
        {"jsonrpc":"2.0","method":"agent.approval.pending","params":{"id":"00000000-0000-0000-0000-000000000001","agent":"claudeCode","kind":"command","command":"rm -rf /","cwd":"/home/user","risk":3,"contentHash":"c5fca73ef15566810d568ca87f42cf1d917e78ce9c51d9b641a6d783c4c5c7b3"}}
        """.data(using: .utf8)!
        let event = DaemonEvent.decode(from: json)
        if case .approvalPending(let p) = event {
            #expect(p.contentHash == "c5fca73ef15566810d568ca87f42cf1d917e78ce9c51d9b641a6d783c4c5c7b3")
            #expect(p.approvalContentHash == p.contentHash)
        } else {
            Issue.record("Expected .approvalPending")
        }
    }

    @Test("approval pending decode tolerates a missing contentHash (legacy daemon)")
    func approvalPendingDecodeMissingContentHash() throws {
        let json = """
        {"jsonrpc":"2.0","method":"agent.approval.pending","params":{"id":"00000000-0000-0000-0000-000000000001","agent":"claudeCode","kind":"command","command":"rm -rf /","cwd":"/home/user","risk":3}}
        """.data(using: .utf8)!
        let event = DaemonEvent.decode(from: json)
        if case .approvalPending(let p) = event {
            #expect(p.contentHash == nil)
        } else {
            Issue.record("Expected .approvalPending")
        }
    }

    @Test("unknown method returns unknown event")
    func unknownMethod() {
        let json = """
        {"jsonrpc":"2.0","method":"session.attach","params":{}}
        """.data(using: .utf8)!
        if case .unknown(let method) = DaemonEvent.decode(from: json) {
            #expect(method == "session.attach")
        } else {
            Issue.record("Expected .unknown")
        }
    }

    @Test("framing round-trip")
    func framingRoundTrip() {
        let payload = Data("hello".utf8)
        let framed = DaemonFraming.frame(payload)
        #expect(framed.count == 4 + payload.count)
        if let (unframed, rest) = DaemonFraming.unframe(framed) {
            #expect(unframed == payload)
            #expect(rest.isEmpty)
        } else {
            Issue.record("unframe returned nil")
        }
    }

    @Test("unframe returns nil when incomplete")
    func incompleteFrame() {
        let data = Data([0, 0, 0, 10, 1, 2])  // says 10 bytes but only 2 available
        #expect(DaemonFraming.unframe(data) == nil)
    }

    @Test("multi-frame parsing")
    func multiFrame() {
        let msg1 = Data("first".utf8)
        let msg2 = Data("second".utf8)
        var buf = DaemonFraming.frame(msg1)
        buf.append(DaemonFraming.frame(msg2))

        let (m1, rest1) = DaemonFraming.unframe(buf)!
        #expect(m1 == msg1)
        let (m2, rest2) = DaemonFraming.unframe(rest1)!
        #expect(m2 == msg2)
        #expect(rest2.isEmpty)
    }

    // MARK: - Conversation attachment wire contract (Go 7df8b831 golden fixtures)

    @Test func attachmentReferenceDecodesGoldenImageWithMimeType() throws {
        let golden = ConversationAttachmentGoldenFixtures.attachmentImageWithMimeType
        let decoded = try JSONDecoder().decode(
            ConversationAttachmentReference.self, from: Data(golden.utf8)
        )
        #expect(decoded == sampleImageAttachment)
    }

    @Test func attachmentReferenceEncodesGoldenImageWithMimeType() throws {
        let golden = try goldenJSONObject(ConversationAttachmentGoldenFixtures.attachmentImageWithMimeType)
        let encoded = try encodedJSONObject(sampleImageAttachment)
        #expect(jsonObjectsEqual(encoded, golden))
    }

    @Test func attachmentReferenceDecodesGoldenFileWithoutMimeType() throws {
        let golden = ConversationAttachmentGoldenFixtures.attachmentFileWithoutMimeType
        let decoded = try JSONDecoder().decode(
            ConversationAttachmentReference.self, from: Data(golden.utf8)
        )
        #expect(decoded == sampleFileAttachmentNoMime)
    }

    @Test func attachmentReferenceEncodesGoldenFileWithoutMimeType() throws {
        let golden = try goldenJSONObject(ConversationAttachmentGoldenFixtures.attachmentFileWithoutMimeType)
        let encoded = try encodedJSONObject(sampleFileAttachmentNoMime)
        #expect(jsonObjectsEqual(encoded, golden))
    }

    @Test func appendNewChatWithAttachmentsGoldenRoundTrip() throws {
        let goldenJSON = ConversationAttachmentGoldenFixtures.appendNewChatWithAttachments
        let decoded = try JSONDecoder().decode(
            ConversationAppendRequest.self, from: Data(goldenJSON.utf8)
        )
        #expect(decoded.conversationId == nil)
        #expect(decoded.baseSeq == 0)
        #expect(decoded.clientTurnId == "ios-device-uuid:1")
        #expect(decoded.agent == "claudeCode")
        #expect(decoded.cwd == "~")
        #expect(decoded.prompt == "Describe this image")
        #expect(decoded.model == "sonnet")
        #expect(decoded.budgetUSD == 5.0)
        #expect(decoded.attachments == [sampleImageAttachment])

        let golden = try goldenJSONObject(goldenJSON)
        let encoded = try encodedJSONObject(decoded)
        #expect(jsonObjectsEqual(encoded, golden))
    }

    @Test func appendFollowUpWithAttachmentsGoldenRoundTrip() throws {
        let goldenJSON = ConversationAttachmentGoldenFixtures.appendFollowUpWithAttachments
        let decoded = try JSONDecoder().decode(
            ConversationAppendRequest.self, from: Data(goldenJSON.utf8)
        )
        #expect(decoded.conversationId == "conv_1")
        #expect(decoded.baseSeq == 42)
        #expect(decoded.clientTurnId == "ios-device-uuid:2")
        #expect(decoded.prompt == "Now add a regression test")
        #expect(decoded.attachments == [sampleImageAttachment])

        let golden = try goldenJSONObject(goldenJSON)
        let encoded = try encodedJSONObject(decoded)
        #expect(jsonObjectsEqual(encoded, golden))
    }

    @Test func appendLegacyNewChatWithoutAttachmentsGoldenRoundTrip() throws {
        let goldenJSON = ConversationAttachmentGoldenFixtures.appendLegacyNewChatWithoutAttachments
        let decoded = try JSONDecoder().decode(
            ConversationAppendRequest.self, from: Data(goldenJSON.utf8)
        )
        #expect(decoded.attachments == nil)

        let golden = try goldenJSONObject(goldenJSON)
        let encoded = try encodedJSONObject(decoded)
        #expect(jsonObjectsEqual(encoded, golden))
        let encodedObj = encoded as! [String: Any]
        #expect(encodedObj["attachments"] == nil)
    }

    @Test func turnWithAttachmentsGoldenRoundTrip() throws {
        let goldenJSON = ConversationAttachmentGoldenFixtures.turnWithAttachments
        let decoded = try JSONDecoder().decode(
            ConversationTurnEnvelope.self, from: Data(goldenJSON.utf8)
        )
        #expect(decoded.attachments == [sampleImageAttachment])

        let golden = try goldenJSONObject(goldenJSON)
        let encoded = try encodedJSONObject(decoded)
        #expect(jsonObjectsEqual(encoded, golden))
    }

    @Test func turnLegacyWithoutAttachmentsGoldenRoundTrip() throws {
        let goldenJSON = ConversationAttachmentGoldenFixtures.turnLegacyWithoutAttachments
        let decoded = try JSONDecoder().decode(
            ConversationTurnEnvelope.self, from: Data(goldenJSON.utf8)
        )
        #expect(decoded.id == "turn_1")
        #expect(decoded.vendorSessionId == "sess_abc")
        #expect(decoded.completedAt == "2026-07-03T01:05:00Z")
        #expect(decoded.errorMessage == "exit code 1")
        #expect(decoded.attachments.isEmpty)

        let golden = try goldenJSONObject(goldenJSON)
        let encoded = try encodedJSONObject(decoded)
        #expect(jsonObjectsEqual(encoded, golden))
        let encodedObj = encoded as! [String: Any]
        #expect(encodedObj["attachments"] == nil)
    }

    @Test func turnDefaultEmptyAttachmentsOmitsAttachmentsKey() throws {
        let goldenJSON = ConversationAttachmentGoldenFixtures.turnDefaultEmptyAttachments
        let decoded = try JSONDecoder().decode(
            ConversationTurnEnvelope.self, from: Data(goldenJSON.utf8)
        )
        #expect(decoded.attachments.isEmpty)

        let golden = try goldenJSONObject(goldenJSON)
        let encoded = try encodedJSONObject(decoded)
        #expect(jsonObjectsEqual(encoded, golden))
        let encodedObj = encoded as! [String: Any]
        #expect(encodedObj["attachments"] == nil)
    }

    @Test func conversationTurnDecodesWhenAttachmentsKeyIsAbsent() throws {
        let data = Data(ConversationAttachmentGoldenFixtures.turnDefaultEmptyAttachments.utf8)
        let turn = try JSONDecoder().decode(ConversationTurnEnvelope.self, from: data)
        #expect(turn.attachments.isEmpty)
    }

    @Test func conversationAppendRequestOmitsAttachmentsWhenNilOrEmpty() throws {
        let nilRequest = ConversationAppendRequest(clientTurnId: "ct1", prompt: "hello")
        let nilJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(nilRequest)) as! [String: Any]
        #expect(nilJSON["attachments"] == nil)

        let emptyRequest = ConversationAppendRequest(
            clientTurnId: "ct1", prompt: "hello", attachments: []
        )
        let emptyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(emptyRequest)) as! [String: Any]
        #expect(emptyJSON["attachments"] == nil)
    }

    @Test func conversationAttachmentRejectsMalformedKind() throws {
        let data = Data(#"{"id":"a1","name":"x","byteCount":1,"kind":"video","hostPath":"/p","previewCacheKey":"a1"}"#.utf8)
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(ConversationAttachmentReference.self, from: data)
        }
    }

    @Test func conversationAttachmentDecodesLegacyWithoutContentDigest() throws {
        let data = Data(ConversationAttachmentGoldenFixtures.attachmentImageWithMimeType.utf8)
        let decoded = try JSONDecoder().decode(ConversationAttachmentReference.self, from: data)
        #expect(decoded.contentDigest == nil)
        #expect(decoded.id == "a1")
    }

    @Test func conversationAttachmentRoundTripsContentDigest() throws {
        let digest = String(repeating: "ab", count: 32)
        let ref = ConversationAttachmentReference(
            id: "a1", name: "photo.jpg", mimeType: "image/jpeg",
            byteCount: 12, kind: .image,
            hostPath: "/Users/me/.lancer/attachments/objects/\(digest)",
            previewCacheKey: "a1",
            contentDigest: digest
        )
        let encoded = try JSONEncoder().encode(ref)
        let obj = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        #expect(obj["contentDigest"] as? String == digest)
        let decoded = try JSONDecoder().decode(ConversationAttachmentReference.self, from: encoded)
        #expect(decoded == ref)
    }
}
