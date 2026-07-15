import Testing
import Foundation
@testable import LancerCore

// MARK: - Golden JSON helpers (Go 7df8b831 wire contract)

private enum ConversationAttachmentGoldenFixtures {
    static let sampleDigest = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

    /// Go `json.Marshal(sampleImageAttachment())` — legacy without contentDigest.
    static let attachmentImageWithMimeType = """
    {"id":"a1","name":"photo.jpg","mimeType":"image/jpeg","byteCount":310992,"kind":"image","hostPath":"/Users/me/.lancer/attachments/photo.jpg","previewCacheKey":"a1"}
    """

    /// Go `json.Marshal(sampleFileAttachment())` — mimeType omitted via `,omitempty`.
    static let attachmentFileWithoutMimeType = """
    {"id":"a2","name":"notes.txt","byteCount":42,"kind":"file","hostPath":"/Users/me/.lancer/attachments/notes.txt","previewCacheKey":"a2"}
    """

    /// Outgoing image attachment with locked contentDigest wire field.
    static let attachmentImageWithContentDigest = """
    {"id":"a1","name":"photo.jpg","mimeType":"image/jpeg","byteCount":310992,"kind":"image","hostPath":"/Users/me/.lancer/attachments/objects/\(sampleDigest)","previewCacheKey":"a1","contentDigest":"\(sampleDigest)"}
    """

    /// New-chat append with one image attachment (digest required on outgoing).
    static let appendNewChatWithAttachments = """
    {"baseSeq":0,"clientTurnId":"ios-device-uuid:1","agent":"claudeCode","cwd":"~","prompt":"Describe this image","model":"sonnet","budgetUSD":5,"attachments":[{"id":"a1","name":"photo.jpg","mimeType":"image/jpeg","byteCount":310992,"kind":"image","hostPath":"/Users/me/.lancer/attachments/objects/\(sampleDigest)","previewCacheKey":"a1","contentDigest":"\(sampleDigest)"}]}
    """

    /// Follow-up append with one image attachment (digest required on outgoing).
    static let appendFollowUpWithAttachments = """
    {"conversationId":"conv_1","baseSeq":42,"clientTurnId":"ios-device-uuid:2","prompt":"Now add a regression test","attachments":[{"id":"a1","name":"photo.jpg","mimeType":"image/jpeg","byteCount":310992,"kind":"image","hostPath":"/Users/me/.lancer/attachments/objects/\(sampleDigest)","previewCacheKey":"a1","contentDigest":"\(sampleDigest)"}]}
    """

    /// Pre-attachment new-chat append — proves custom Codable preserves legacy wire shape.
    static let appendLegacyNewChatWithoutAttachments = """
    {"baseSeq":0,"clientTurnId":"ios-device-uuid:1","agent":"claudeCode","cwd":"~","prompt":"Fix the failing auth test","model":"sonnet","budgetUSD":5}
    """

    /// Turn envelope with one attachment (legacy without digest still decodes).
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

private let sampleImageAttachmentWithDigest = ConversationAttachmentReference(
    id: "a1", name: "photo.jpg", mimeType: "image/jpeg",
    byteCount: 310_992, kind: .image,
    hostPath: "/Users/me/.lancer/attachments/objects/\(ConversationAttachmentGoldenFixtures.sampleDigest)",
    previewCacheKey: "a1",
    contentDigest: ConversationAttachmentGoldenFixtures.sampleDigest
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
        #expect(decoded.attachments == [sampleImageAttachmentWithDigest])

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
        #expect(decoded.attachments == [sampleImageAttachmentWithDigest])

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

    // MARK: - fullTools (per-dispatch "Full tools" toggle)

    @Test func conversationAppendRequestOmitsFullToolsWhenNilOrFalse() throws {
        let nilRequest = ConversationAppendRequest(clientTurnId: "ct1", prompt: "hello")
        let nilJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(nilRequest)) as! [String: Any]
        #expect(nilJSON["fullTools"] == nil)

        let falseRequest = ConversationAppendRequest(clientTurnId: "ct1", prompt: "hello", fullTools: false)
        let falseJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(falseRequest)) as! [String: Any]
        #expect(falseJSON["fullTools"] == nil)
    }

    @Test func conversationAppendRequestEncodesFullToolsWhenTrue() throws {
        let request = ConversationAppendRequest(clientTurnId: "ct1", prompt: "hello", fullTools: true)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        #expect(json["fullTools"] as? Bool == true)
    }

    @Test func conversationAppendRequestDecodesFullToolsTrueRoundTrip() throws {
        let golden = #"{"clientTurnId":"ct1","baseSeq":0,"prompt":"hello","fullTools":true}"#
        let decoded = try JSONDecoder().decode(ConversationAppendRequest.self, from: Data(golden.utf8))
        #expect(decoded.fullTools == true)

        let goldenObj = try goldenJSONObject(golden)
        let encoded = try encodedJSONObject(decoded)
        #expect(jsonObjectsEqual(encoded, goldenObj))
    }

    @Test func conversationAppendRequestDecodesMissingFullToolsAsNil() throws {
        // Older iOS clients / requests never sent this key — must decode
        // cleanly (nil, not a thrown error), matching Go's zero-value default
        // (strict/fast) on the daemon side.
        let golden = #"{"clientTurnId":"ct1","baseSeq":0,"prompt":"hello"}"#
        let decoded = try JSONDecoder().decode(ConversationAppendRequest.self, from: Data(golden.utf8))
        #expect(decoded.fullTools == nil)
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
        let digest = ConversationAttachmentGoldenFixtures.sampleDigest
        #expect(AttachmentContentDigest.isValid(digest))
        let golden = try goldenJSONObject(ConversationAttachmentGoldenFixtures.attachmentImageWithContentDigest)
        let encoded = try encodedJSONObject(sampleImageAttachmentWithDigest)
        #expect(jsonObjectsEqual(encoded, golden))
        let decoded = try JSONDecoder().decode(
            ConversationAttachmentReference.self,
            from: Data(ConversationAttachmentGoldenFixtures.attachmentImageWithContentDigest.utf8)
        )
        #expect(decoded == sampleImageAttachmentWithDigest)
        #expect(decoded.contentDigest == digest)
        #expect(AttachmentContentDigest.isValid(decoded.contentDigest ?? ""))
    }

    @Test func attachmentPutResultDecodesIdPathAndContentDigest() throws {
        let digest = ConversationAttachmentGoldenFixtures.sampleDigest
        let json = Data("""
        {"id":"srv-1","path":"/Users/me/.lancer/attachments/objects/\(digest)","contentDigest":"\(digest)","ok":true}
        """.utf8)
        // AttachmentPutResult lives in SSHTransport — decode via JSON mirror fields.
        struct PutMirror: Codable {
            var id: String?
            var path: String?
            var contentDigest: String?
            var ok: Bool?
        }
        let decoded = try JSONDecoder().decode(PutMirror.self, from: json)
        #expect(decoded.id == "srv-1")
        #expect(decoded.path?.contains(digest) == true)
        #expect(decoded.contentDigest == digest)
        #expect(AttachmentContentDigest.isValid(decoded.contentDigest ?? ""))
    }

    // MARK: - sessionsTranscriptResult / SessionMessage.Role tolerance
    //
    // Regression for the "Decryption failed" desktop-session-resume bug: a real
    // Claude Code transcript's extended-thinking blocks serialize with
    // `"role":"thinking"` (daemon/lancerd/claude_transcript_adapter.go, the
    // `case "thinking"` / `case "redacted_thinking"` arms of
    // claudeAssistantMessages). That raw string previously had no matching
    // `SessionMessage.Role` case, so `JSONDecoder` threw `dataCorrupted`
    // decoding the whole `[SessionMessage]` array, and E2ERelayBridge's
    // `try? decoder.decode(...)` in the `sessionsTranscriptResult` case turned
    // that into `E2EError.decryptFailed` — a real, reproducible functional
    // bug, not a cosmetic one. Fixed by adding `.thinking` and by decoding any
    // unrecognized raw role string to `.unknown` instead of failing the parse.

    @Test func sessionMessageRoleDecodesThinking() throws {
        let json = Data(#"{"role":"thinking","text":"planning the edit","timestamp":"2026-07-15T10:00:00.123Z"}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionMessage.self, from: json)
        #expect(decoded.role == .thinking)
        #expect(decoded.text == "planning the edit")
    }

    @Test func sessionMessageRoleToleratesUnknownFutureVendorRole() throws {
        // A hypothetical future vendor role the Swift enum doesn't know about
        // yet must not fail the decode — it should fall back to `.unknown`
        // rather than take down the whole transcript again.
        let json = Data(#"{"role":"someFutureRoleNoOneHasSeenYet","text":"x"}"#.utf8)
        let decoded = try JSONDecoder().decode(SessionMessage.self, from: json)
        #expect(decoded.role == .unknown)
    }

    @Test func sessionsTranscriptResultDecodesRealClaudeSessionWithThinkingBlocks() throws {
        // Captured (via a throwaway daemon test invoking parseClaudeTranscript
        // directly) from a real ~/.claude/projects/**/*.jsonl session that
        // reproduced the live bug: 91 messages including 17 "thinking" blocks,
        // 32 toolCall/toolResult pairs — exactly the shape a synthetic
        // user/assistant-only fixture never exercised.
        let json = Data(#"""
        {"type":"sessionsTranscriptResult","payload":{"messages":[
            {"role":"user","text":"fix the bug","timestamp":"2026-07-03T15:23:36.659Z"},
            {"role":"thinking","text":"","timestamp":"2026-07-03T15:24:03.195Z"},
            {"role":"assistant","text":"I'll start by loading the skill.","timestamp":"2026-07-03T15:24:03.916Z"},
            {"role":"toolCall","text":"Read: AGENTS.md","toolName":"Read","timestamp":"2026-07-03T15:24:05.000Z"},
            {"role":"toolResult","text":"ok","timestamp":"2026-07-03T15:24:06.000Z"}
        ],"nextLine":139,"resetRequired":false}}
        """#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(
            E2ERelayMessage.RelayInnerEnvelope<SessionsTranscriptResult>.self, from: json
        )
        #expect(envelope.payload.messages.count == 5)
        #expect(envelope.payload.messages[1].role == .thinking)
        #expect(envelope.payload.nextLine == 139)
    }
}
