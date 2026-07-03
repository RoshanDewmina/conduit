import Foundation
import Testing
@testable import LancerCore
@testable import SyncKit

@Suite("ConversationCloudRecords")
struct ConversationCloudRecordsTests {

    @Test("ConversationTurnChunkPayload round-trips a turn and its events through JSON")
    func turnChunkPayloadJSONRoundTrip() throws {
        let turn = ChatTurn(
            id: "turn-1", conversationID: "conv-1", ordinal: 0,
            prompt: "hello", runID: "run-1", status: .completed,
            assistantText: "hi there", hostSeqStart: 1, hostSeqEnd: 3
        )
        let events = [
            ChatEvent(conversationID: "conv-1", seq: 1, turnID: "turn-1", kind: "prompt", text: "hello"),
            ChatEvent(conversationID: "conv-1", seq: 2, turnID: "turn-1", kind: "output", text: "hi "),
            ChatEvent(conversationID: "conv-1", seq: 3, turnID: "turn-1", kind: "output", text: "there"),
        ]
        let payload = ConversationTurnChunkPayload(turn: turn, events: events)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ConversationTurnChunkPayload.self, from: data)

        #expect(decoded.turn.id == turn.id)
        #expect(decoded.turn.assistantText == "hi there")
        #expect(decoded.events.map(\.seq) == [1, 2, 3])
        #expect(decoded.events.map(\.text) == ["hello", "hi ", "there"])
    }

    @Test("conversationRecord/conversation round-trip is a no-op off iOS")
    func conversationRecordNoOpOffIOS() {
        let conv = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        let wrapper = ConversationCloudRecords.conversationRecord(from: conv, zoneName: ConversationSyncEngine.zoneName)
        #if os(iOS)
        #expect(wrapper.recordName == conv.id)
        #else
        #expect(wrapper.recordName == "")
        #endif
    }
}
