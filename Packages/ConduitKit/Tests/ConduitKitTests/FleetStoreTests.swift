import Testing
import Foundation
@testable import ConduitCore
#if os(iOS)
@testable import AppFeature
@testable import InboxFeature
#endif

// MARK: - Cross-platform slot management tests (FleetSlotManager)
//
// ``FleetSlotManager<T>`` is the platform-independent core of ``FleetStore``.
// These tests run on macOS via `swift test` without requiring UIKit or any
// iOS-only types.

private struct MockSlot: Identifiable {
    let id: UUID
    let name: String
    init(_ name: String = "host") { self.id = UUID(); self.name = name }
}

@Suite("FleetSlotManager — slot management")
struct FleetSlotManagerTests {

    @Test("add one slot — count is 1 and store is not full")
    func addSlot() {
        var mgr = FleetSlotManager<MockSlot>()
        mgr.add(MockSlot("server-a"))
        #expect(mgr.slots.count == 1)
        #expect(!mgr.isFull)
    }

    @Test("fill to maxSlots — isFull is true and count equals maxSlots")
    func fillToMax() {
        var mgr = FleetSlotManager<MockSlot>()
        for i in 0..<FleetSlotManager<MockSlot>.maxSlots {
            mgr.add(MockSlot("host-\(i)"))
        }
        #expect(mgr.isFull)
        #expect(mgr.slots.count == FleetSlotManager<MockSlot>.maxSlots)
    }

    @Test("add a 4th slot when max is 3 — count stays at 3")
    func addBeyondMax() {
        var mgr = FleetSlotManager<MockSlot>()
        for i in 0..<(FleetSlotManager<MockSlot>.maxSlots + 1) {
            mgr.add(MockSlot("host-\(i)"))
        }
        #expect(mgr.slots.count == FleetSlotManager<MockSlot>.maxSlots)
    }

    @Test("remove the only slot — slots is empty")
    func removeSlot() {
        var mgr = FleetSlotManager<MockSlot>()
        let s = MockSlot("server-b")
        mgr.add(s)
        mgr.remove(id: s.id)
        #expect(mgr.slots.isEmpty)
    }

    @Test("remove with unknown id — slots unchanged")
    func removeUnknownID() {
        var mgr = FleetSlotManager<MockSlot>()
        mgr.add(MockSlot("server-c"))
        mgr.remove(id: UUID())
        #expect(mgr.slots.count == 1)
    }

    @Test("remove one of two slots — the other slot is preserved")
    func removeOneOfTwo() {
        var mgr = FleetSlotManager<MockSlot>()
        let a = MockSlot("alpha")
        let b = MockSlot("beta")
        mgr.add(a)
        mgr.add(b)
        mgr.remove(id: a.id)
        #expect(mgr.slots.count == 1)
        #expect(mgr.slots[0].id == b.id)
    }

    @Test("remove then re-add — slot count reaches max again")
    func addAfterRemove() {
        var mgr = FleetSlotManager<MockSlot>()
        var added: [MockSlot] = []
        for i in 0..<FleetSlotManager<MockSlot>.maxSlots {
            let s = MockSlot("host-\(i)")
            mgr.add(s)
            added.append(s)
        }
        #expect(mgr.isFull)
        mgr.remove(id: added[0].id)
        #expect(!mgr.isFull)
        mgr.add(MockSlot("replacement"))
        #expect(mgr.slots.count == FleetSlotManager<MockSlot>.maxSlots)
        #expect(mgr.isFull)
    }

    @Test("maxSlots constant is 3")
    func maxSlotsIs3() {
        #expect(FleetSlotManager<MockSlot>.maxSlots == 3)
    }

    @Test("empty manager — isFull is false and slots is empty")
    func emptyManagerState() {
        let mgr = FleetSlotManager<MockSlot>()
        #expect(!mgr.isFull)
        #expect(mgr.slots.isEmpty)
    }

    @Test("slots are returned in insertion order")
    func insertionOrder() {
        var mgr = FleetSlotManager<MockSlot>()
        let names = ["first", "second", "third"]
        names.forEach { mgr.add(MockSlot($0)) }
        let returned = mgr.slots.map(\.name)
        #expect(returned == names)
    }

    @Test("repeated remove of same id is idempotent")
    func doubleRemoveIdempotent() {
        var mgr = FleetSlotManager<MockSlot>()
        let s = MockSlot("only")
        mgr.add(s)
        mgr.remove(id: s.id)
        mgr.remove(id: s.id)  // second remove should not crash
        #expect(mgr.slots.isEmpty)
    }
}

// MARK: - iOS-only FleetStore tests
//
// These tests require iOS-only types (InboxViewModel) and are compiled away
// on macOS. They run when the test suite is executed via Xcode / on a simulator.

#if os(iOS)
@Suite("FleetStore — iOS approval aggregation")
@MainActor
struct FleetStoreTests {

    /// Verify the maxSlots constant is propagated from FleetSlotManager.
    @Test("FleetStore.maxSlots is 3")
    func maxSlotsIs3() {
        #expect(FleetStore.maxSlots == 3)
    }

    /// allPendingApprovals sums pending (undecided) approvals across all inbox
    /// view models. We test the arithmetic via InboxViewModel directly because
    /// constructing a real FleetStore.Slot requires SessionViewModel + DaemonChannel
    /// (SSH infrastructure) that can't be spun up in a unit test.
    @Test("allPendingApprovals formula: sum of pending counts across viewmodels")
    func allPendingApprovalsMath() {
        let makeApproval: (Bool) -> Approval = { decided in
            var a = Approval(
                sessionID: SessionID(),
                agent: .claudeCode,
                kind: .command,
                command: "ls",
                cwd: "/"
            )
            if decided {
                a.decision = .approved
                a.decidedAt = .now
            }
            return a
        }

        // Inbox 1: 2 pending
        let vm1 = InboxViewModel()
        vm1.approvals = [makeApproval(false), makeApproval(false)]

        // Inbox 2: 1 pending, 1 decided
        let vm2 = InboxViewModel()
        vm2.approvals = [makeApproval(false), makeApproval(true)]

        // Inbox 3: 0 pending (all decided)
        let vm3 = InboxViewModel()
        vm3.approvals = [makeApproval(true)]

        // Replicate the FleetStore.allPendingApprovals formula.
        let vms: [InboxViewModel] = [vm1, vm2, vm3]
        let total = vms.reduce(0) { $0 + $1.approvals.filter(\.isPending).count }
        #expect(total == 3)
    }

    /// slot(forApprovalID:) returns nil when the store is empty.
    @Test("slot(forApprovalID:) returns nil on empty store")
    func slotForApprovalIDEmpty() {
        let store = FleetStore()
        let result = store.slot(forApprovalID: ApprovalID())
        #expect(result == nil)
    }
}
#endif
