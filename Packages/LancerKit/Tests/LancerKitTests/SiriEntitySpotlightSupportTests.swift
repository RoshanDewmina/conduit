import Foundation
import Testing
@testable import PersistenceKit

@Suite("IntentEntitySpotlightSupport")
struct IntentEntitySpotlightSupportTests {
    @Test("conversation index fields exclude search snippets and secrets")
    func conversationFieldsPrivacy() {
        let record = IntentConversationRecord(
            id: "conv-1",
            title: "Auth refactor",
            hostName: "Mac Studio",
            workspacePath: "/Users/dev/my-project",
            vendor: "claudeCode",
            lastActivityAt: .now,
            searchSnippet: "api_key=sk-live-SECRET token bearer"
        )
        let fields = IntentEntitySpotlightSupport.ConversationIndexFields(record)
        #expect(fields.title == "Auth refactor")
        #expect(fields.workspaceFolderName == "my-project")
        #expect(!fields.title.contains("api_key"))
        let serialized = [fields.title, fields.hostName, fields.workspaceFolderName].joined(separator: " ")
        #expect(!IntentEntitySpotlightSupport.containsForbiddenIndexMaterial(serialized))
    }

    @Test("machine and workspace IDs stay stable when labels change")
    func stableIDsAcrossRename() {
        let machineA = IntentMachineRecord(
            id: "relay:550e8400-e29b-41d4-a716-446655440000",
            displayName: "Old Name",
            hostName: "old.local",
            kind: .relayMachine
        )
        let machineB = IntentMachineRecord(
            id: "relay:550e8400-e29b-41d4-a716-446655440000",
            displayName: "New Name",
            hostName: "new.local",
            kind: .relayMachine
        )
        #expect(machineA.id == machineB.id)

        let workspaceA = IntentWorkspaceRecord(
            id: "ws-stable",
            name: "Before",
            machineID: "550e8400-e29b-41d4-a716-446655440000",
            path: "/repo",
            lastUsedAt: .now
        )
        let workspaceB = IntentWorkspaceRecord(
            id: "ws-stable",
            name: "After",
            machineID: "550e8400-e29b-41d4-a716-446655440000",
            path: "/repo-renamed",
            lastUsedAt: .now
        )
        #expect(workspaceA.id == workspaceB.id)
        #expect(IntentEntitySpotlightSupport.stableWorkspaceID(workspaceA) == IntentEntitySpotlightSupport.stableWorkspaceID(workspaceB))
    }

    @Test("syncable conversation stable ID prefers cloud record name")
    func syncableConversationStableID() {
        let stable = IntentEntitySpotlightSupport.syncableConversationStableID(
            conversationID: "local-conv",
            cloudRecordName: "ck-record-42"
        )
        #expect(stable == "ck-record-42")

        let localOnly = IntentEntitySpotlightSupport.syncableConversationStableID(
            conversationID: "local-conv",
            cloudRecordName: nil
        )
        #expect(localOnly == "local-conv")
    }
}
