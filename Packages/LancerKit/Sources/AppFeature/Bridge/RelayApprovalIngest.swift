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

    /// Fleet-wide pending approvals (one most-recent per machine). Home banner
    /// and other cross-machine surfaces read this instead of a single
    /// `activeMachineID` lookup.
    public var allPendingApprovals: [(machineID: RelayMachineID, approval: Approval)] {
        latestPendingApproval
            .compactMap { machineID, approval -> (RelayMachineID, Approval)? in
                guard approval.isPending else { return nil }
                return (machineID, approval)
            }
            .sorted { $0.1.createdAt > $1.1.createdAt }
    }

    private let database: AppDatabase
    private var listenTask: Task<Void, Never>?
    /// Dedup for Live Activity pending-count pushes so identical ingest/decide
    /// refreshes don't spam ActivityKit.
    private var lastLiveActivityPendingCount: Int?
    private var lastLiveActivityHighestRisk: Int?
    private var lastLiveActivityPendingID: String?

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

        let repository = ApprovalRepository(database)
        do {
            try await repository.upsert(approval)
        } catch {
            return
        }

        // Refresh the Home Screen PendingApprovalsWidget now that a new
        // approval is pending. This is the ONLY production "new approval
        // arrives" path — the SSH-based `ApprovalIngest` actor that also
        // calls this is only reachable through the dead `FleetStore`/`Slot`
        // type, never constructed by AppRoot/WorkspacesView — so without
        // this call the widget's count/summary in UserDefaults never
        // updates on arrival and only ever changes as a side effect of a
        // later in-app decision (`ApprovalRelay.enqueue`), leaving the
        // widget stale until then.
        await repository.writeApprovalWidgetSnapshot()

        // Do not skip this — without a registered origin, `ApprovalRelay
        // .forwardDecisionOnly` falls through to SSH/backend-relay paths that
        // don't exist in this app and the decision is queued forever.
        ApprovalRelay.shared.registerRelayOrigin(approvalID: approval.id.uuidString, machineID: machineID)
        latestPendingApproval[machineID] = approval

        // Keep any running Live Activity's pending count in sync with the
        // fleet-wide DB (same signal Dynamic Island exists for).
        await publishLiveActivityPendingApprovals(using: repository)
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
        await publishLiveActivityPendingApprovals(using: ApprovalRepository(database))
    }

    /// Pushes fleet-wide pending count + highest risk + the most recent
    /// pending approval's ID to every running Live Activity. The ID drives
    /// the Lock Screen / Dynamic Island Approve/Reject buttons (they only
    /// render when non-nil — MAJOR-14) so it must be included in the dedup
    /// key, not just count/risk: a resolved approval replaced by a different
    /// pending one of the same count/risk must still refresh which ID the
    /// buttons act on. Deduped so identical refreshes are no-ops.
    private func publishLiveActivityPendingApprovals(using repository: ApprovalRepository) async {
        guard #available(iOS 16.2, *) else { return }
        let pending = (try? await repository.pending()) ?? []
        let count = pending.count
        let highestRisk: Int? = count > 0 ? pending.map(\.risk.rawValue).max() : nil
        // `pending()` orders by createdAt DESC — the most recently arrived
        // pending approval is the one surfaced for the buttons.
        let mostRecentID: String? = count > 0 ? pending.first?.id.uuidString : nil
        if count == lastLiveActivityPendingCount,
           highestRisk == lastLiveActivityHighestRisk,
           mostRecentID == lastLiveActivityPendingID {
            return
        }
        lastLiveActivityPendingCount = count
        lastLiveActivityHighestRisk = highestRisk
        lastLiveActivityPendingID = mostRecentID
        await LancerLiveActivityManager.shared.updatePendingApprovals(
            count, highestRisk: highestRisk, pendingApprovalID: mostRecentID
        )
    }

    #if DEBUG
    /// UITest / SEED_DEMO: surface the first DB-seeded pending approval so
    /// home-banner + `LiveThreadView` can render without a live relay.
    /// Prefers `preferredMachineID` (a paired machine) when provided; otherwise
    /// the stable UITest machine id.
    public func hydratePendingForUITestIfRequested(
        preferredMachineID: RelayMachineID? = nil
    ) async {
        let uitest = ProcessInfo.processInfo.environment["LANCER_UITEST_RESEED"] == "1"
        let seedDemo = ProcessInfo.processInfo.environment["LANCER_SEED_DEMO"] == "1"
        guard uitest || seedDemo else { return }
        guard allPendingApprovals.isEmpty else { return }
        let repo = ApprovalRepository(database)
        guard let approval = try? await repo.pending().first else { return }
        let machineID = preferredMachineID ?? Self.uitestMachineID
        ApprovalRelay.shared.registerRelayOrigin(approvalID: approval.id.uuidString, machineID: machineID)
        latestPendingApproval[machineID] = approval
    }

    public static let uitestMachineID = RelayMachineID(UUID(uuidString: "00000000-0000-0000-0000-0000000000e2")!)
    #endif
}
#endif
