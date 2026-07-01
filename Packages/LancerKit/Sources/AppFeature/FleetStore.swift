#if os(iOS)
import Foundation
import Observation
import LancerCore
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
        /// Latest ``agent.status`` snapshot from the bridge (when refreshed).
        public var bridgeStatus: AgentStatusSnapshot?
        /// Current E2E relay state for this slot's daemon connection.
        public var relayState: Session.RelayState

        public init(
            id: UUID = UUID(),
            hostID: HostID,
            hostName: String,
            sessionViewModel: SessionViewModel,
            channel: DaemonChannel,
            ingest: ApprovalIngest,
            inboxVM: LiveInboxViewModel,
            bridgeStatus: AgentStatusSnapshot? = nil,
            relayState: Session.RelayState = .none
        ) {
            self.id = id
            self.hostID = hostID
            self.hostName = hostName
            self.sessionViewModel = sessionViewModel
            self.channel = channel
            self.ingest = ingest
            self.inboxVM = inboxVM
            self.bridgeStatus = bridgeStatus
            self.relayState = relayState
        }
    }

    /// Refresh ``agent.status`` for every connected slot.
    public func refreshBridgeStatus() async {
        for slot in slots where slot.sessionViewModel.status == .connected {
            guard let snap = try? await slot.channel.fetchAgentStatus() else { continue }
            manager.update(id: slot.id) { $0.bridgeStatus = snap }
        }
    }

    /// First slot with pending approvals (for jump-to-unread).
    public func firstSlotWithPendingApprovals() -> Slot? {
        slots.first { slot in
            slot.inboxVM.approvals.contains { $0.isPending && $0.sessionID == slot.sessionViewModel.sessionID }
        }
    }

    /// Maximum number of concurrent sessions. Matches ``FleetSlotManager.maxSlots``.
    public static var maxSlots: Int { FleetSlotManager<Slot>.maxSlots }

    /// Backing store — uses the cross-platform ``FleetSlotManager`` for all
    /// add/remove/isFull logic so it can be unit-tested independently.
    private var manager = FleetSlotManager<Slot>()

    /// All currently active slots, in insertion order.
    public var slots: [Slot] { manager.slots }

    /// Approvals delivered over a relay pairing — not a fleet slot (there's
    /// no SSH session), so `attentionItems`'s per-slot loop below never sees
    /// them on its own. AppRoot sets this to whichever inbox VM its
    /// `lancerE2EApprovalReceived` handler inserts relay approvals into,
    /// keeping it in sync automatically. Without this, a relay-only user —
    /// V1's primary transport, SSH is legacy — would never see a pending
    /// approval on Home: it would escalate, wait out the fail-closed
    /// timeout, and deny, with nothing ever rendering on screen.
    public var relayInboxVM: InboxViewModel?

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

    /// Replace a slot's daemon channel + approval ingest after a reconnect
    /// re-arm (MAJOR-4), keeping the new objects retained by the store.
    public func rearm(slotID: UUID, channel: DaemonChannel, ingest: ApprovalIngest) {
        manager.update(id: slotID) { slot in
            slot.channel = channel
            slot.ingest = ingest
        }
    }

    /// Set the E2E relay state on every slot. The relay client is app-wide
    /// (one pairing), so its pairing/connection state applies to all live slots.
    public func setRelayStateOnAllSlots(_ state: Session.RelayState) {
        for slot in slots {
            manager.update(id: slot.id) { $0.relayState = state }
        }
    }

    /// The one honest connection state for a single slot — derived from the
    /// authoritative `SessionViewModel.status` plus the slot's relay state. This
    /// is the single source of truth both the Fleet header and the top status
    /// bar read from, so they can never disagree (Finding #9).
    public func connectionState(for slot: Slot) -> Session.ConnectionState {
        Session.ConnectionState.derive(
            session: slot.sessionViewModel.status,
            relay: slot.relayState
        )
    }

    /// The fleet-wide honest connection state: the "best" (most-live) state
    /// across all slots. Used for app-shell affordances that summarise the whole
    /// fleet (e.g. the per-tab "bridge connected" header). Never reports
    /// `.connected` just because a slot exists — only when one is actually live.
    public var connectionState: Session.ConnectionState {
        guard !slots.isEmpty else { return .offline }
        let states = slots.map { connectionState(for: $0) }
        // Order by liveness: connected > relayPaired > connecting > failed > offline.
        if states.contains(.connected)    { return .connected }
        if states.contains(.relayPaired)  { return .relayPaired }
        if states.contains(.connecting)   { return .connecting }
        if states.contains(.failed)       { return .failed }
        return .offline
    }

    /// Sum of pending approvals across all live inboxes.
    public var allPendingApprovals: Int {
        slots.reduce(0) { $0 + $1.inboxVM.approvals.filter(\.isPending).count }
    }

    public var attentionItems: [AttentionItem] {
        var items: [AttentionItem] = []
        var seenApprovalIDs: Set<String> = []
        for slot in slots {
            for approval in slot.inboxVM.approvals where approval.isPending || approval.decision == .expired {
                let item = AttentionItem(approval: approval)
                items.append(item)
                seenApprovalIDs.insert(item.id)
            }
            if connectionState(for: slot) == .offline,
               slot.inboxVM.approvals.contains(where: \.isPending) {
                items.append(AttentionItem(offlineHost: slot.hostID, hostName: slot.hostName))
            }
        }
        if let relayInboxVM {
            for approval in relayInboxVM.approvals where approval.isPending || approval.decision == .expired {
                let item = AttentionItem(approval: approval)
                // Defensive: skip if a slot's own inbox somehow already
                // surfaced the same approval, so a single pending decision
                // can never count twice.
                guard !seenApprovalIDs.contains(item.id) else { continue }
                items.append(item)
            }
        }
        return items.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return $0.createdAt < $1.createdAt
        }
    }

    /// Finds the slot whose inbox contains an approval with the given ID.
    /// Used by cross-session decision routing (e.g. Watch approve, lock-screen intent).
    public func slot(forApprovalID approvalID: ApprovalID) -> Slot? {
        slots.first { $0.inboxVM.approvals.contains { $0.id == approvalID } }
    }
}
#endif
