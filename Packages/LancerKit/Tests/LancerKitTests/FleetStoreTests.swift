import Testing
import Foundation
@testable import LancerCore
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
                cwd: "/",
                risk: .low
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

    /// Regression for a real bug found 2026-07-01: a relay-only pairing (no
    /// SSH fleet slot) delivers approvals into a separate inbox VM that the
    /// per-slot loop in `attentionItems` never saw, so Home's headline/cards/
    /// badge — all sourced from `attentionItems` — never showed a pending
    /// relay approval at all. It escalated, waited out the 120s fail-closed
    /// timeout, and denied, invisibly. `relayInboxVM` closes that gap.
    @Test("attentionItems includes a pending approval from relayInboxVM with zero slots")
    func attentionItemsIncludesRelayOnlyApproval() {
        let store = FleetStore()
        #expect(store.slots.isEmpty)

        let relayVM = InboxViewModel()
        relayVM.approvals = [
            Approval(sessionID: SessionID(), agent: .claudeCode, kind: .fileWrite, command: "write tc.txt", cwd: "/tmp", risk: .medium)
        ]
        store.relayInboxVM = relayVM

        #expect(store.attentionItems.count == 1)
    }

    /// A decided (already approved/denied) relay approval must not linger as
    /// an attention item — only pending or expired ones should surface.
    @Test("attentionItems excludes a decided relayInboxVM approval")
    func attentionItemsExcludesDecidedRelayApproval() {
        let store = FleetStore()
        var decided = Approval(sessionID: SessionID(), agent: .claudeCode, kind: .fileWrite, command: "write tc.txt", cwd: "/tmp", risk: .medium)
        decided.decision = .approved
        decided.decidedAt = .now

        let relayVM = InboxViewModel()
        relayVM.approvals = [decided]
        store.relayInboxVM = relayVM

        #expect(store.attentionItems.isEmpty)
    }

    /// With no relayInboxVM set at all (the pre-fix default state), attentionItems
    /// must stay empty rather than crash on a nil reference.
    @Test("attentionItems is empty when relayInboxVM is nil and there are no slots")
    func attentionItemsEmptyWithoutRelayInboxVM() {
        let store = FleetStore()
        #expect(store.relayInboxVM == nil)
        #expect(store.attentionItems.isEmpty)
    }
}

/// Content-hash binding (WWDC26 security audit): `InboxViewModel.decide` must
/// echo the resolved approval's `contentHash` back through `decisionSink` so
/// every phone-side decide path can forward it to lancerd's
/// `approvalStore.resolve`, which rejects a decision whose hash doesn't match.
/// Without this, every real approval a user taps on device would be denied.
@Suite("InboxViewModel — decisionSink content-hash threading")
@MainActor
struct InboxViewModelContentHashTests {

    @Test("decide passes the approval's contentHash through decisionSink")
    func decidePassesContentHash() throws {
        let hash = Approval.computeContentHash(command: "rm -rf build", patch: nil, cwd: "/repo", toolInput: nil)
        let approval = Approval(
            sessionID: SessionID(),
            agent: .claudeCode,
            kind: .command,
            command: "rm -rf build",
            cwd: "/repo",
            risk: .high,
            contentHash: hash
        )
        let vm = InboxViewModel(approvals: [approval])

        var captured: (ApprovalID, Approval.Decision, String?, String?)?
        vm.decisionSink = { id, decision, editedToolInput, contentHash in
            captured = (id, decision, editedToolInput, contentHash)
        }

        vm.decide(approval.id, decision: .approved)

        let (id, decision, editedToolInput, contentHash) = try #require(captured)
        #expect(id == approval.id)
        #expect(decision == .approved)
        #expect(editedToolInput == nil)
        #expect(contentHash == hash)
    }

    @Test("decide passes nil contentHash when the approval never carried one")
    func decidePassesNilContentHashWhenAbsent() {
        let approval = Approval(
            sessionID: SessionID(),
            agent: .codex,
            kind: .command,
            command: "ls",
            cwd: "/tmp",
            risk: .low
        )
        let vm = InboxViewModel(approvals: [approval])

        var capturedHash: String??
        vm.decisionSink = { _, _, _, contentHash in
            capturedHash = contentHash
        }

        vm.decide(approval.id, decision: .rejected)

        #expect(capturedHash != nil, "decisionSink must fire")
        #expect((capturedHash ?? nil) == nil)
    }
}
#endif
