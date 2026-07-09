import Foundation
import Testing
@testable import AppFeature

@Suite struct CursorTrustedMachineModelTests {
    @Test("shortMachineID uses first 8 UUID characters uppercase")
    func shortMachineIDFormat() {
        let uuid = UUID(uuidString: "a1b2c3d4-e5f6-7890-abcd-ef1234567890")!
        #expect(CursorTrustedMachineFormatting.shortMachineID(uuid) == "A1B2C3D4")
    }

    @Test("connectionStatusLabel reflects live connection")
    func connectionStatusLabel() {
        #expect(CursorTrustedMachineFormatting.connectionStatusLabel(isConnected: true) == "Connected")
        #expect(CursorTrustedMachineFormatting.connectionStatusLabel(isConnected: false) == "Offline")
    }

    @Test("pairedSinceLabel is nil without a date")
    func pairedSinceNil() {
        #expect(CursorTrustedMachineFormatting.pairedSinceLabel(pairedAt: nil) == nil)
    }

    @Test("pairedSinceLabel prefixes relative pairing time")
    func pairedSinceRelative() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let pairedAt = now.addingTimeInterval(-86_400)
        let label = CursorTrustedMachineFormatting.pairedSinceLabel(pairedAt: pairedAt, now: now)
        #expect(label?.hasPrefix("Paired ") == true)
    }

    @Test("removeConfirmationMessage warns when pending approvals exist")
    func removeConfirmationPendingWarning() {
        let message = CursorTrustedMachineFormatting.removeConfirmationMessage(
            displayName: "Mac Mini",
            pendingApprovalCount: 2
        )
        #expect(message.contains("2 pending approvals"))
        #expect(message.contains("will not decide them"))
    }

    @Test("removeConfirmationMessage is direct when no pending approvals")
    func removeConfirmationClean() {
        let message = CursorTrustedMachineFormatting.removeConfirmationMessage(
            displayName: "Mac Mini",
            pendingApprovalCount: 0
        )
        #expect(message.contains("Remove Mac Mini from this phone?"))
        #expect(!message.contains("pending"))
    }

    @Test("buildRows maps machine inputs and pending counts")
    func buildRows() {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let rows = CursorTrustedMachineSnapshot.buildRows(
            machines: [
                .init(
                    id: id,
                    displayName: "Studio Mac",
                    pairedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    isConnected: true,
                    isInvalid: false
                ),
            ],
            pendingApprovalCounts: [id: 1]
        )
        #expect(rows.count == 1)
        #expect(rows[0].id == id.uuidString)
        #expect(rows[0].displayName == "Studio Mac")
        #expect(rows[0].shortMachineID == "11111111")
        #expect(rows[0].isConnected)
        #expect(rows[0].pendingApprovalCount == 1)
        #expect(!rows[0].isInvalid)
    }

    @Test("mockRows provides two static examples for the mock shell")
    func mockRows() {
        #expect(CursorTrustedMachineSnapshot.mockRows.count == 2)
        #expect(CursorTrustedMachineSnapshot.mockRows.allSatisfy { !$0.isInvalid })
    }
}
