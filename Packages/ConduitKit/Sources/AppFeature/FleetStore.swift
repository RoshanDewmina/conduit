#if os(iOS)
import Foundation
import Observation
import ConduitCore
import SSHTransport
import InboxFeature
import SessionFeature

// NOTE: ApprovalRelay (ws-i) does NOT exist on feat/hosted-agents-rc.
// FleetStore is designed to work with the RC's direct-DB approval path
// (ApprovalActionIntent). When ws-i lands and introduces ApprovalRelay,
// a small follow-up is needed: register each slot's channel with the relay
// in AppRoot.startSession() so lock-screen intents can route decisions to
// the correct DaemonChannel. See ApprovalActionIntent.swift for the current
// direct-DB write path.

/// A multi-slot session store that holds up to `maxSlots` concurrent live
/// sessions, each identified by a stable UUID.
///
/// FleetStore is additive — the existing single-slot path in AppRoot
/// (`sessionViewModel`, `daemonChannel`, etc.) is preserved for backwards
/// compatibility with the current UI. FleetStore is the parallel multi-slot
/// layer that enables cross-session features such as "approve from fleet".
@MainActor @Observable
public final class FleetStore {

    /// One active SSH session with its supporting objects.
    public struct Slot: Identifiable, Sendable {
        public let id: UUID
        public let hostID: HostID
        public let hostName: String
        public var sessionViewModel: SessionViewModel
        public var channel: DaemonChannel
        public var ingest: ApprovalIngest
        public var inboxVM: LiveInboxViewModel

        public init(
            id: UUID = UUID(),
            hostID: HostID,
            hostName: String,
            sessionViewModel: SessionViewModel,
            channel: DaemonChannel,
            ingest: ApprovalIngest,
            inboxVM: LiveInboxViewModel
        ) {
            self.id = id
            self.hostID = hostID
            self.hostName = hostName
            self.sessionViewModel = sessionViewModel
            self.channel = channel
            self.ingest = ingest
            self.inboxVM = inboxVM
        }
    }

    /// Maximum number of concurrent sessions. Matches ``FleetSlotManager.maxSlots``.
    public static var maxSlots: Int { FleetSlotManager<Slot>.maxSlots }

    /// Backing store — uses the cross-platform ``FleetSlotManager`` for all
    /// add/remove/isFull logic so it can be unit-tested independently.
    private var manager = FleetSlotManager<Slot>()

    /// All currently active slots, in insertion order.
    public var slots: [Slot] { manager.slots }

    public init() {}

    /// Whether the store has reached capacity.
    public var isFull: Bool { manager.isFull }

    /// Add a slot. Silently drops the call if the store is full.
    public func add(_ slot: Slot) {
        manager.add(slot)
    }

    /// Remove the slot with the given id, if present.
    public func remove(id: UUID) {
        manager.remove(id: id)
    }

    /// Sum of pending approvals across all live inboxes.
    public var allPendingApprovals: Int {
        slots.reduce(0) { $0 + $1.inboxVM.approvals.filter(\.isPending).count }
    }

    /// Finds the slot whose inbox contains an approval with the given ID.
    /// Used by cross-session decision routing (e.g. Watch approve, lock-screen intent).
    public func slot(forApprovalID approvalID: ApprovalID) -> Slot? {
        slots.first { $0.inboxVM.approvals.contains { $0.id == approvalID } }
    }
}
#endif
