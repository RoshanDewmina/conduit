#if os(iOS)
import Foundation
import Observation
import LancerCore
import PersistenceKit
import SessionFeature

/// M4: the missing link between `E2ERelayBridge.handleRelayMessage`'s
/// `"approvalPending"` case (`Packages/LancerKit/Sources/SessionFeature/E2ERelayBridge.swift`)
/// — which already posts a `lancerE2EApprovalReceived` `NotificationCenter`
/// notification for every incoming relay approval — and the rest of the app.
/// Before this type, nothing subscribed to that notification at all; it was
/// posted into the void. This actor-isolated (`@MainActor`) observer
/// persists each incoming approval, registers its relay origin with
/// `ApprovalRelay.shared` (so a later Approve/Deny routes back to the exact
/// machine it arrived from — `ApprovalRelay.forwardDecisionOnly` is
/// fail-closed without this call, the decision would otherwise be parked in
/// the redelivery queue forever), and publishes the most recent pending
/// approval per machine for `LiveThreadView` to render as an in-thread card.
///
/// SCOPE LIMITATION (deliberate, not an oversight — read before extending):
/// `E2ERelayMessage.ApprovalData` (the relay wire type, see
/// `Packages/LancerKit/Sources/LancerCore/E2ERelayMessage.swift`) carries no
/// `runId`/`sessionId`, unlike the SSH-side `ApprovalPendingParams`. That
/// means a relay-delivered approval cannot be correlated to the specific
/// conversation/run it belongs to — the only correlation this milestone has
/// is "which paired machine did this arrive from." `latestPendingApproval`
/// is therefore keyed by `RelayMachineID`, not by run/conversation: it is a
/// machine-scoped convenience surface for the active live thread, not a
/// run-level guarantee. This matches the product direction that Inbox
/// remains the system of record for approvals. Tightening this to run-level
/// precision would require a daemon-side wire change (out of scope here).
@MainActor
@Observable
public final class RelayApprovalIngest {
    /// The most recently ingested pending approval per machine. `LiveThreadView`
    /// looks this up by `ShellLiveBridge.activeMachineID` — see the scope
    /// limitation above for why this is machine-scoped, not run-scoped.
    public private(set) var latestPendingApproval: [RelayMachineID: Approval] = [:]

    private let database: AppDatabase
    private var listenTask: Task<Void, Never>?

    public init(database: AppDatabase) {
        self.database = database
    }

    /// Starts observing `lancerE2EApprovalReceived`. Idempotent — a second
    /// call while already listening is a no-op, matching the established
    /// `for await notification in NotificationCenter.default.notifications(named:)`
    /// idiom used elsewhere in this codebase (pre-wipe `AppRoot`'s status/APNs/
    /// Live Activity token subscribers).
    public func start() {
        guard listenTask == nil else { return }
        listenTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: Notification.Name("lancerE2EApprovalReceived")
            ) {
                guard let self else { return }
                await self.handle(notification)
            }
        }
    }

    private func handle(_ notification: Notification) async {
        guard
            let approvalData = notification.userInfo?["approvalData"] as? E2ERelayMessage.ApprovalData,
            let machineID = notification.userInfo?["machineID"] as? RelayMachineID
        else { return }

        // Same fallback pattern as `ApprovalPendingParams.approvalRisk`/
        // `.approvalKind`/`.approvalAgent` (LancerDProtocol.swift ~line 86-93)
        // for the SSH path — mirrored here for the relay path.
        let approval = Approval(
            id: ApprovalID(UUID(uuidString: approvalData.approvalID) ?? UUID()),
            sessionID: SessionID(),
            agent: Approval.AgentSource(rawValue: approvalData.agent) ?? .unknown,
            kind: Approval.Kind(rawValue: approvalData.kind) ?? .command,
            command: approvalData.command,
            patch: approvalData.patch,
            cwd: approvalData.cwd ?? "",
            risk: Approval.Risk(rawValue: min(approvalData.risk, 3)) ?? .high,
            toolName: approvalData.toolName,
            toolInput: approvalData.toolInput,
            lastStateChangeAt: .now,
            contentHash: approvalData.contentHash
        )

        do {
            try await ApprovalRepository(database).upsert(approval)
        } catch {
            return
        }

        // Do not skip this — without a registered origin, `ApprovalRelay
        // .forwardDecisionOnly` falls through to SSH/backend-relay paths that
        // don't exist in this app and the decision is queued forever.
        ApprovalRelay.shared.registerRelayOrigin(approvalID: approval.id.uuidString, machineID: machineID)
        latestPendingApproval[machineID] = approval
    }

    /// Entry point for the in-thread Approve/Deny buttons. Forwards through
    /// `ApprovalRelay.shared.enqueue`, which persists the decision, audits it,
    /// and forwards it via the bridge registered above. Clears the published
    /// card only if it still matches this approval's id — a newer approval
    /// arriving on the same machine mid-decision must not be clobbered.
    public func decide(_ approval: Approval, decision: Approval.Decision, machineID: RelayMachineID) async {
        await ApprovalRelay.shared.enqueue(
            approvalID: approval.id.uuidString,
            decision: decision,
            db: database,
            hostID: machineID.uuidString
        )
        if latestPendingApproval[machineID]?.id == approval.id {
            latestPendingApproval[machineID] = nil
        }
    }
}
#endif
