import Testing
import Foundation
@testable import LancerCore

/// Regression coverage for the `deviceRegistered` reply (daemon → phone), added
/// to close the gap where a relay-only pairing (no SSH host) never learned its
/// per-session capability token: `ApprovalRelay.relayToken` stayed empty for the
/// life of the process, so `postDecisionToBackend` — the only fallback when the
/// direct `approvalResponse` send doesn't get acked — silently no-opped on
/// every call. See `daemon/lancerd/e2e_router.go`'s `deviceRegister` case and
/// `E2ERelayBridge.handleRelayMessage`'s new `"deviceRegistered"` case.
///
/// This pins the wire *shape* the Go side actually emits
/// (`{"type":"deviceRegistered","payload":{"relayToken":"…"}}`) against the
/// Swift decode path, since a shape mismatch would fail silently behind a
/// `try?` and reintroduce the exact bug this fixes with no compiler warning.
@Suite struct E2ERelayMessageWireTests {
    @Test("deviceRegistered envelope decodes the daemon's relayToken")
    func decodesDaemonShape() throws {
        // Exactly what daemon/lancerd/e2e_router.go marshals:
        // json.Marshal(map[string]interface{}{"type": "deviceRegistered", "payload": map[string]interface{}{"relayToken": relayToken}})
        let wireJSON = #"{"type":"deviceRegistered","payload":{"relayToken":"abc123secret"}}"#
        let data = Data(wireJSON.utf8)

        let env = try JSONDecoder().decode(
            E2ERelayMessage.RelayInnerEnvelope<E2ERelayMessage.DeviceRegisteredData>.self, from: data
        )

        #expect(env.type == "deviceRegistered")
        #expect(env.payload.relayToken == "abc123secret")
    }

    @Test("DeviceRegisteredData round-trips through encode/decode")
    func roundTrips() throws {
        let original = E2ERelayMessage.DeviceRegisteredData(relayToken: "tok-xyz")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(E2ERelayMessage.DeviceRegisteredData.self, from: data)
        #expect(decoded.relayToken == original.relayToken)
    }

    // Content-hash binding: the phone's decision must echo back the same
    // contentHash the daemon stamped on the pending ApprovalData, so
    // approvalStore.resolve (daemon/lancerd/approval.go) can verify it. This
    // pins that DecisionData actually carries the field through encode/decode
    // over the relay wire.
    @Test("DecisionData round-trips contentHash through encode/decode")
    func decisionDataRoundTripsContentHash() throws {
        let original = E2ERelayMessage.DecisionData(
            approvalID: "appr-1", decision: "approve", editedToolInput: nil,
            contentHash: "c5fca73ef15566810d568ca87f42cf1d917e78ce9c51d9b641a6d783c4c5c7b3"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(E2ERelayMessage.DecisionData.self, from: data)
        #expect(decoded.contentHash == original.contentHash)
        #expect(decoded.approvalID == original.approvalID)
    }

    @Test("DecisionData contentHash defaults to nil when omitted")
    func decisionDataContentHashDefaultsNil() {
        let d = E2ERelayMessage.DecisionData(approvalID: "appr-2", decision: "deny", editedToolInput: nil)
        #expect(d.contentHash == nil)
    }

    // MARK: - Conversation sync (Task 5, cross-device conversation sync)
    //
    // These pin the wire shapes daemon/lancerd/conversation_store.go and
    // conversation_rpc.go actually emit (per their Go struct `json:` tags)
    // against the Swift decode path, for both the SSH JSON-RPC result shape
    // (LancerDProtocol.swift types decoded directly) and the E2E relay
    // envelope shape ({"type":"...Result","payload":{...}}, with an "error"
    // key added into the flattened payload by e2e_router.go's
    // conversationRelayPayload on failure).

    @Test("ConversationSummary decodes the daemon's full shape (conversation_store.go conversationSummary)")
    func conversationSummaryDecodesFullShape() throws {
        // Every field present, including the four `,omitempty` fields
        // (hostID, model, budgetUSD, archivedAt).
        let wireJSON = """
        {"id":"conv_1","title":"Fix auth redirect","provider":"claudeCode","agentID":"claudeCode",\
        "hostID":"host_abc","hostName":"Roshan MacBook","cwd":"/Users/roshan/project","model":"sonnet",\
        "budgetUSD":5.0,"state":"active","source":"phone","createdAt":"2026-07-03T00:30:00Z",\
        "updatedAt":"2026-07-03T01:00:00Z","lastActivityAt":"2026-07-03T01:00:00Z","lastSeq":42,\
        "archivedAt":"2026-07-03T02:00:00Z","lastTurnID":"turn_9","lastTurnStatus":"failed"}
        """
        let summary = try JSONDecoder().decode(ConversationSummary.self, from: Data(wireJSON.utf8))
        #expect(summary.id == "conv_1")
        #expect(summary.title == "Fix auth redirect")
        #expect(summary.provider == "claudeCode")
        #expect(summary.agentID == "claudeCode")
        #expect(summary.hostID == "host_abc")
        #expect(summary.hostName == "Roshan MacBook")
        #expect(summary.cwd == "/Users/roshan/project")
        #expect(summary.model == "sonnet")
        #expect(summary.budgetUSD == 5.0)
        #expect(summary.state == "active")
        #expect(summary.source == "phone")
        #expect(summary.lastSeq == 42)
        #expect(summary.archivedAt == "2026-07-03T02:00:00Z")
        #expect(summary.lastTurnID == "turn_9")
        #expect(summary.lastTurnStatus == "failed")
    }

    @Test("ConversationSummary decodes with all omitempty fields absent")
    func conversationSummaryDecodesMinimalShape() throws {
        // hostID/model/budgetUSD/archivedAt/lastTurn* all have `,omitempty` in Go and are
        // omitted entirely (not null) when zero-valued — this is the shape a
        // freshly created conversation actually has.
        let wireJSON = """
        {"id":"conv_2","title":"New conversation","provider":"claudeCode","agentID":"claudeCode",\
        "hostName":"Roshan MacBook","cwd":"/Users/roshan","state":"active","source":"phone",\
        "createdAt":"2026-07-03T00:30:00Z","updatedAt":"2026-07-03T00:30:00Z",\
        "lastActivityAt":"2026-07-03T00:30:00Z","lastSeq":1}
        """
        let summary = try JSONDecoder().decode(ConversationSummary.self, from: Data(wireJSON.utf8))
        #expect(summary.hostID == nil)
        #expect(summary.model == nil)
        #expect(summary.budgetUSD == nil)
        #expect(summary.archivedAt == nil)
        #expect(summary.lastTurnID == nil)
        #expect(summary.lastTurnStatus == nil)
        #expect(summary.lastSeq == 1)
    }

    @Test("ConversationTurnEnvelope decodes the daemon's shape (conversationTurn)")
    func conversationTurnEnvelopeDecodesShape() throws {
        let wireJSON = """
        {"id":"turn_1","conversationId":"conv_1","ordinal":2,"clientTurnId":"ios-uuid:2",\
        "prompt":"Now add a regression test","runId":"run_2","provider":"claudeCode",\
        "vendorSessionId":"sess_abc","status":"failed","startedAt":"2026-07-03T01:00:00Z",\
        "completedAt":"2026-07-03T01:05:00Z","errorMessage":"exit code 1"}
        """
        let turn = try JSONDecoder().decode(ConversationTurnEnvelope.self, from: Data(wireJSON.utf8))
        #expect(turn.id == "turn_1")
        #expect(turn.conversationId == "conv_1")
        #expect(turn.ordinal == 2)
        #expect(turn.clientTurnId == "ios-uuid:2")
        #expect(turn.runId == "run_2")
        #expect(turn.vendorSessionId == "sess_abc")
        #expect(turn.status == "failed")
        #expect(turn.completedAt == "2026-07-03T01:05:00Z")
        #expect(turn.errorMessage == "exit code 1")
    }

    @Test("ConversationTurnEnvelope decodes a running turn with no vendor session bound yet")
    func conversationTurnEnvelopeDecodesRunningShape() throws {
        // vendorSessionId/completedAt/errorMessage all `,omitempty` and absent
        // — this is the shape a just-dispatched, not-yet-resolved turn has.
        let wireJSON = """
        {"id":"turn_2","conversationId":"conv_1","ordinal":1,"clientTurnId":"ios-uuid:1",\
        "prompt":"Fix the failing auth test","runId":"run_1","provider":"claudeCode",\
        "status":"running","startedAt":"2026-07-03T00:30:00Z"}
        """
        let turn = try JSONDecoder().decode(ConversationTurnEnvelope.self, from: Data(wireJSON.utf8))
        #expect(turn.vendorSessionId == nil)
        #expect(turn.completedAt == nil)
        #expect(turn.errorMessage == nil)
        #expect(turn.status == "running")
    }

    @Test("ConversationEvent decodes an output event (conversationEvent)")
    func conversationEventDecodesOutputShape() throws {
        let wireJSON = """
        {"conversationId":"conv_1","seq":5,"turnId":"turn_1","runId":"run_1","kind":"output",\
        "stream":"stdout","text":"hello world","createdAt":"2026-07-03T00:30:05Z"}
        """
        let event = try JSONDecoder().decode(ConversationEvent.self, from: Data(wireJSON.utf8))
        #expect(event.seq == 5)
        #expect(event.kind == "output")
        #expect(event.stream == "stdout")
        #expect(event.text == "hello world")
        #expect(event.role == nil)
        #expect(event.payloadJson == nil)
    }

    @Test("ConversationEvent decodes a bare turn_started event with only required fields")
    func conversationEventDecodesMinimalShape() throws {
        let wireJSON = """
        {"conversationId":"conv_1","seq":1,"turnId":"turn_1","runId":"run_1",\
        "kind":"turn_started","createdAt":"2026-07-03T00:30:00Z"}
        """
        let event = try JSONDecoder().decode(ConversationEvent.self, from: Data(wireJSON.utf8))
        #expect(event.stream == nil)
        #expect(event.text == nil)
        #expect(event.role == nil)
        #expect(event.payloadJson == nil)
    }

    @Test("ConversationEvent decodes a status event with a payloadJson blob")
    func conversationEventDecodesStatusShape() throws {
        let wireJSON = #"""
        {"conversationId":"conv_1","seq":6,"turnId":"turn_1","runId":"run_1","kind":"status",\#
        "payloadJson":"{\"status\":\"completed\"}","createdAt":"2026-07-03T00:31:00Z"}
        """#
        let event = try JSONDecoder().decode(ConversationEvent.self, from: Data(wireJSON.utf8))
        #expect(event.kind == "status")
        #expect(event.payloadJson == "{\"status\":\"completed\"}")
    }

    @Test("ConversationArtifactEnvelope decodes the daemon's shape (conversationArtifact)")
    func conversationArtifactEnvelopeDecodesShape() throws {
        let wireJSON = #"""
        {"id":"artifact_1","conversationId":"conv_1","turnId":"turn_1","runId":"run_1","kind":"diff",\#
        "title":"auth.go","summary":"Fixed redirect bug","payloadJson":"{\"diff\":\"...\"}",\#
        "status":"ready","createdAt":"2026-07-03T00:30:10Z","updatedAt":"2026-07-03T00:30:10Z"}
        """#
        let artifact = try JSONDecoder().decode(ConversationArtifactEnvelope.self, from: Data(wireJSON.utf8))
        #expect(artifact.id == "artifact_1")
        #expect(artifact.turnId == "turn_1")
        #expect(artifact.kind == "diff")
        #expect(artifact.title == "auth.go")
        #expect(artifact.summary == "Fixed redirect bug")
        #expect(artifact.status == "ready")
    }

    @Test("ConversationListResponse decodes the daemon's shape (conversationListResult)")
    func conversationListResponseDecodesShape() throws {
        let wireJSON = """
        {"conversations":[{"id":"conv_1","title":"Fix auth redirect","provider":"claudeCode",\
        "agentID":"claudeCode","hostName":"Roshan MacBook","cwd":"/Users/roshan/project",\
        "state":"active","source":"phone","createdAt":"2026-07-03T00:30:00Z",\
        "updatedAt":"2026-07-03T01:00:00Z","lastActivityAt":"2026-07-03T01:00:00Z","lastSeq":42}],\
        "nextCursor":""}
        """
        let response = try JSONDecoder().decode(ConversationListResponse.self, from: Data(wireJSON.utf8))
        #expect(response.conversations.count == 1)
        #expect(response.conversations.first?.id == "conv_1")
        #expect(response.nextCursor == "")
        #expect(response.error == nil)
    }

    // Go's `[]conversationSummary` marshals a nil slice as JSON `null` (not
    // `[]`) when the daemon has zero conversations — a plain non-optional
    // `decode([T].self, forKey:)` throws on `null`. This pins that the custom
    // decoder defends against it instead of crashing on an empty ledger.
    @Test("ConversationListResponse defaults conversations to [] when the daemon sends null")
    func conversationListResponseDecodesNullConversations() throws {
        let wireJSON = #"{"conversations":null,"nextCursor":""}"#
        let response = try JSONDecoder().decode(ConversationListResponse.self, from: Data(wireJSON.utf8))
        #expect(response.conversations.isEmpty)
    }

    @Test("ConversationListResponse surfaces the relay-added error field")
    func conversationListResponseDecodesRelayError() throws {
        let wireJSON = #"{"conversations":null,"nextCursor":"","error":"conversation store unavailable"}"#
        let response = try JSONDecoder().decode(ConversationListResponse.self, from: Data(wireJSON.utf8))
        #expect(response.error == "conversation store unavailable")
    }

    @Test("ConversationFetchResponse decodes the daemon's shape (conversationFetchResult)")
    func conversationFetchResponseDecodesShape() throws {
        let wireJSON = """
        {"conversation":{"id":"conv_1","title":"Fix auth redirect","provider":"claudeCode",\
        "agentID":"claudeCode","hostName":"Roshan MacBook","cwd":"/Users/roshan/project",\
        "state":"active","source":"phone","createdAt":"2026-07-03T00:30:00Z",\
        "updatedAt":"2026-07-03T01:00:00Z","lastActivityAt":"2026-07-03T01:00:00Z","lastSeq":42},\
        "turns":[],"events":[],"artifacts":[],"nextSeq":42,"hasMore":false}
        """
        let response = try JSONDecoder().decode(ConversationFetchResponse.self, from: Data(wireJSON.utf8))
        #expect(response.conversation.id == "conv_1")
        #expect(response.turns.isEmpty)
        #expect(response.events.isEmpty)
        #expect(response.artifacts.isEmpty)
        #expect(response.nextSeq == 42)
        #expect(response.hasMore == false)
    }

    // Same nil-slice-marshals-null defense as ConversationListResponse, for
    // all three list fields independently — an empty conversation (just
    // created, no turns/events/artifacts yet) has all three as Go nil slices.
    @Test("ConversationFetchResponse defaults turns/events/artifacts to [] when the daemon sends null")
    func conversationFetchResponseDecodesNullLists() throws {
        let wireJSON = """
        {"conversation":{"id":"conv_1","title":"New conversation","provider":"claudeCode",\
        "agentID":"claudeCode","hostName":"Roshan MacBook","cwd":"/Users/roshan","state":"active",\
        "source":"phone","createdAt":"2026-07-03T00:30:00Z","updatedAt":"2026-07-03T00:30:00Z",\
        "lastActivityAt":"2026-07-03T00:30:00Z","lastSeq":0},\
        "turns":null,"events":null,"artifacts":null,"nextSeq":0,"hasMore":false}
        """
        let response = try JSONDecoder().decode(ConversationFetchResponse.self, from: Data(wireJSON.utf8))
        #expect(response.turns.isEmpty)
        #expect(response.events.isEmpty)
        #expect(response.artifacts.isEmpty)
    }

    @Test("ConversationFetchResponse surfaces the relay-added error field on a not-found conversation")
    func conversationFetchResponseDecodesRelayError() throws {
        let wireJSON = """
        {"conversation":{"id":"","title":"","provider":"","agentID":"","hostName":"","cwd":"",\
        "state":"","source":"","createdAt":"","updatedAt":"","lastActivityAt":"","lastSeq":0},\
        "turns":null,"events":null,"artifacts":null,"nextSeq":0,"hasMore":false,\
        "error":"conversation_store: conversation \\"conv_missing\\" not found"}
        """
        let response = try JSONDecoder().decode(ConversationFetchResponse.self, from: Data(wireJSON.utf8))
        #expect(response.error == "conversation_store: conversation \"conv_missing\" not found")
    }

    @Test("ConversationAppendResponse decodes a started/new-chat shape (conversationAppendResponse)")
    func conversationAppendResponseDecodesStartedShape() throws {
        let wireJSON = """
        {"status":"started","conversationId":"conv_1","turnId":"turn_1","runId":"run_1",\
        "vendorSessionId":"sess_abc","cwd":"/Users/roshan/project","baseSeq":0,"nextSeq":1,\
        "resumeMode":"new"}
        """
        let response = try JSONDecoder().decode(ConversationAppendResponse.self, from: Data(wireJSON.utf8))
        #expect(response.status == "started")
        #expect(response.conversationId == "conv_1")
        #expect(response.turnId == "turn_1")
        #expect(response.runId == "run_1")
        #expect(response.vendorSessionId == "sess_abc")
        #expect(response.cwd == "/Users/roshan/project")
        #expect(response.baseSeq == 0)
        #expect(response.nextSeq == 1)
        #expect(response.resumeMode == "new")
        #expect(response.message == nil)
        #expect(response.rule == nil)
        #expect(response.clientTurnId == nil, "legacy started shape without echo must still decode")
    }

    @Test("ConversationAppendResponse decodes optional clientTurnId echo")
    func conversationAppendResponseDecodesClientTurnIdEcho() throws {
        let wireJSON = """
        {"status":"started","conversationId":"conv_1","turnId":"turn_1","runId":"run_1",\
        "baseSeq":0,"nextSeq":1,"resumeMode":"new","clientTurnId":"ios-device-uuid:1"}
        """
        let response = try JSONDecoder().decode(ConversationAppendResponse.self, from: Data(wireJSON.utf8))
        #expect(response.clientTurnId == "ios-device-uuid:1")
    }

    @Test("ConversationAppendResponse decodes a conflict shape with only the conflict fields present")
    func conversationAppendResponseDecodesConflictShape() throws {
        let wireJSON = """
        {"status":"conflict","conversationId":"conv_1","baseSeq":42,"nextSeq":45,\
        "message":"Conversation changed. Refetch before appending.","clientTurnId":"ios-uuid:conflict"}
        """
        let response = try JSONDecoder().decode(ConversationAppendResponse.self, from: Data(wireJSON.utf8))
        #expect(response.status == "conflict")
        #expect(response.baseSeq == 42)
        #expect(response.nextSeq == 45)
        #expect(response.message == "Conversation changed. Refetch before appending.")
        #expect(response.turnId == nil)
        #expect(response.runId == nil)
        #expect(response.vendorSessionId == nil)
        #expect(response.resumeMode == nil)
        #expect(response.clientTurnId == "ios-uuid:conflict")
    }

    @Test("ConversationArchiveResponse decodes the daemon's shape (conversationArchiveResponse)")
    func conversationArchiveResponseDecodesShape() throws {
        let wireJSON = #"{"ok":true,"conversationId":"conv_1","lastSeq":46}"#
        let response = try JSONDecoder().decode(ConversationArchiveResponse.self, from: Data(wireJSON.utf8))
        #expect(response.ok == true)
        #expect(response.conversationId == "conv_1")
        #expect(response.lastSeq == 46)
        #expect(response.error == nil)
    }

    @Test("ConversationAttachObservedSessionResponse decodes the daemon's shape")
    func conversationAttachObservedSessionResponseDecodesShape() throws {
        let wireJSON = #"{"conversationId":"conv_1","importedEvents":120,"lastSeq":120,"alreadyAttached":false}"#
        let response = try JSONDecoder().decode(ConversationAttachObservedSessionResponse.self, from: Data(wireJSON.utf8))
        #expect(response.conversationId == "conv_1")
        #expect(response.importedEvents == 120)
        #expect(response.lastSeq == 120)
        #expect(response.alreadyAttached == false)
    }

    @Test("ConversationAttachObservedSessionResponse decodes a re-attach as alreadyAttached with no new events")
    func conversationAttachObservedSessionResponseDecodesAlreadyAttached() throws {
        let wireJSON = #"{"conversationId":"conv_1","importedEvents":0,"lastSeq":120,"alreadyAttached":true}"#
        let response = try JSONDecoder().decode(ConversationAttachObservedSessionResponse.self, from: Data(wireJSON.utf8))
        #expect(response.conversationId == "conv_1")
        #expect(response.alreadyAttached == true)
    }

    // A failure (e.g. an unknown on-disk sessionId — see
    // conversation_rpc.go's conversationsAttachObservedSession) surfaces over
    // the relay path as the zero-value response struct plus an added "error" key.
    @Test("ConversationAttachObservedSessionResponse surfaces a relay-path host error")
    func conversationAttachObservedSessionResponseDecodesHostError() throws {
        let wireJSON = """
        {"conversationId":"","importedEvents":0,"lastSeq":0,"alreadyAttached":false,\
        "error":"attachObservedSession: session not found"}
        """
        let response = try JSONDecoder().decode(ConversationAttachObservedSessionResponse.self, from: Data(wireJSON.utf8))
        #expect(response.error == "attachObservedSession: session not found")
    }

    // MARK: - Conversation requests round-trip (phone → daemon encode side)

    @Test("ConversationListRequest encodes with all three fields present (matches Go's non-omitempty request tags)")
    func conversationListRequestEncodesShape() throws {
        let request = ConversationListRequest(limit: 50, cursor: "", includeArchived: false)
        let data = try JSONEncoder().encode(request)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["limit"] as? Int == 50)
        #expect(obj?["cursor"] as? String == "")
        #expect(obj?["includeArchived"] as? Bool == false)
    }

    @Test("ConversationAppendRequest encodes a new-chat request omitting conversationId (matches Go's omitempty)")
    func conversationAppendRequestEncodesNewChatShape() throws {
        let request = ConversationAppendRequest(
            baseSeq: 0, clientTurnId: "ios-device-uuid:1", agent: "claudeCode", cwd: "~",
            prompt: "Fix the failing auth test", model: "sonnet", budgetUSD: 5.0
        )
        let data = try JSONEncoder().encode(request)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["conversationId"] == nil)
        #expect(obj?["clientTurnId"] as? String == "ios-device-uuid:1")
        #expect(obj?["prompt"] as? String == "Fix the failing auth test")
        #expect(obj?["agent"] as? String == "claudeCode")
        #expect(obj?["budgetUSD"] as? Double == 5.0)
    }

    @Test("ConversationAppendRequest encodes a follow-up request with conversationId + baseSeq")
    func conversationAppendRequestEncodesFollowUpShape() throws {
        let request = ConversationAppendRequest(
            conversationId: "conv_1", baseSeq: 42, clientTurnId: "ios-device-uuid:2",
            prompt: "Now add a regression test"
        )
        let data = try JSONEncoder().encode(request)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["conversationId"] as? String == "conv_1")
        #expect(obj?["baseSeq"] as? Int == 42)
        #expect(obj?["prompt"] as? String == "Now add a regression test")
        #expect(obj?["agent"] == nil)
        #expect(obj?["cwd"] == nil)
        #expect(obj?["model"] == nil)
        #expect(obj?["budgetUSD"] == nil)
    }

    @Test("DispatchParams encodes optional contract for agentDispatch relay wire")
    func dispatchParamsEncodesContract() throws {
        let params = E2ERelayMessage.DispatchParams(
            agent: "claudeCode",
            cwd: "~/command-center",
            prompt: "Add proof receipt decode plumbing",
            model: "sonnet",
            budgetUSD: 0,
            contract: ProofReceipt.Contract(
                goal: "Add proof receipt decode plumbing",
                doneCriteria: ["Swift types decode C1 fixture", "Relay runReceipt reaches phone"],
                validationCommands: ["cd Packages/LancerKit && swift test --filter ProofReceiptTests"]
            )
        )
        let data = try JSONEncoder().encode(params)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["agent"] as? String == "claudeCode")
        let contract = obj?["contract"] as? [String: Any]
        #expect(contract?["goal"] as? String == "Add proof receipt decode plumbing")
        #expect((contract?["doneCriteria"] as? [String])?.count == 2)
        #expect((contract?["validationCommands"] as? [String])?.first?.contains("ProofReceiptTests") == true)
    }

    @Test("DispatchParams omits contract key when nil")
    func dispatchParamsOmitsNilContract() throws {
        let params = E2ERelayMessage.DispatchParams(
            agent: "claudeCode", cwd: "~", prompt: "hello"
        )
        let data = try JSONEncoder().encode(params)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["contract"] == nil)
    }

    @Test("ConversationAppendRequest encodes contract on live-bridge append wire")
    func conversationAppendRequestEncodesContract() throws {
        let request = ConversationAppendRequest(
            baseSeq: 0, clientTurnId: "ios-device-uuid:1", agent: "claudeCode", cwd: "~",
            prompt: "Fix the failing auth test",
            contract: ProofReceipt.Contract(
                goal: "Fix the failing auth test",
                doneCriteria: ["Auth test passes"],
                validationCommands: ["swift test --filter AuthTests"]
            )
        )
        let data = try JSONEncoder().encode(request)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let contract = obj?["contract"] as? [String: Any]
        #expect(contract?["goal"] as? String == "Fix the failing auth test")
        #expect((contract?["doneCriteria"] as? [String])?.first == "Auth test passes")
    }

    // MARK: - Conversation relay envelopes ({"type":"...Result","payload":{...}})

    @Test("agentConversationsListResult envelope decodes the daemon's shape")
    func agentConversationsListResultEnvelopeDecodes() throws {
        let wireJSON = """
        {"type":"agentConversationsListResult","payload":{"conversations":[],"nextCursor":""}}
        """
        let env = try JSONDecoder().decode(
            E2ERelayMessage.RelayInnerEnvelope<ConversationListResponse>.self, from: Data(wireJSON.utf8)
        )
        #expect(env.type == "agentConversationsListResult")
        #expect(env.payload.conversations.isEmpty)
        #expect(env.payload.error == nil)
    }

    @Test("agentConversationsAppendResult envelope decodes a started shape")
    func agentConversationsAppendResultEnvelopeDecodes() throws {
        let wireJSON = """
        {"type":"agentConversationsAppendResult","payload":{"status":"started",\
        "conversationId":"conv_1","turnId":"turn_1","runId":"run_1","baseSeq":0,"nextSeq":1,\
        "resumeMode":"new"}}
        """
        let env = try JSONDecoder().decode(
            E2ERelayMessage.RelayInnerEnvelope<ConversationAppendResponse>.self, from: Data(wireJSON.utf8)
        )
        #expect(env.type == "agentConversationsAppendResult")
        #expect(env.payload.status == "started")
        #expect(env.payload.conversationId == "conv_1")
        #expect(env.payload.resumeMode == "new")
    }

    @Test("agentConversationsArchiveResult envelope decodes the daemon's shape")
    func agentConversationsArchiveResultEnvelopeDecodes() throws {
        let wireJSON = """
        {"type":"agentConversationsArchiveResult","payload":{"ok":true,"conversationId":"conv_1","lastSeq":46}}
        """
        let env = try JSONDecoder().decode(
            E2ERelayMessage.RelayInnerEnvelope<ConversationArchiveResponse>.self, from: Data(wireJSON.utf8)
        )
        #expect(env.type == "agentConversationsArchiveResult")
        #expect(env.payload.ok == true)
    }

    @Test("agentConversationsAttachObservedSessionResult envelope surfaces the relay error field")
    func agentConversationsAttachObservedSessionResultEnvelopeDecodesError() throws {
        let wireJSON = """
        {"type":"agentConversationsAttachObservedSessionResult","payload":{"conversationId":"",\
        "importedEvents":0,"lastSeq":0,"alreadyAttached":false,\
        "error":"attachObservedSession: session not found"}}
        """
        let env = try JSONDecoder().decode(
            E2ERelayMessage.RelayInnerEnvelope<ConversationAttachObservedSessionResponse>.self, from: Data(wireJSON.utf8)
        )
        #expect(env.payload.error == "attachObservedSession: session not found")
    }
}
