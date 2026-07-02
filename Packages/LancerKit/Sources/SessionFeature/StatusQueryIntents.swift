#if os(iOS)
import AppIntents
import Foundation
import LancerCore
import PersistenceKit

/// "How many agents are running on Lancer?" — read-only, no in-app approval or
/// mutation. Routes through `CommandGateway.execute(.queryStatus)`, which tries
/// the attached SSH channel then the relay bridge; if neither is live (app never
/// connected this launch, e.g. Siri invoked while the app was fully closed), the
/// intent reports that rather than hanging — see `CommandGateway`'s doc comment.
@available(iOS 17.0, *)
public struct AgentStatusQueryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Agent Status"
    public static let description = IntentDescription("Check how many agent runs are active right now.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        switch await CommandGateway.shared.execute(.queryStatus(homeDir: nil)) {
        case .statusSnapshot(let snapshot):
            let running = snapshot.agents.compactMap(\.runningCount).reduce(0, +)
            if running > 0 {
                return .result(dialog: "\(running) agent run\(running == 1 ? "" : "s") active right now.")
            }
            return .result(dialog: "No agents are currently running.")
        case .timedOut:
            return .result(dialog: "That machine didn't respond in time.")
        case .transportUnavailable, .denied, .ok:
            return .result(dialog: "Lancer isn't connected to a machine right now. Open the app to reconnect.")
        }
    }
}

/// "Are any approvals waiting?" — a purely local read of `ApprovalRepository`,
/// no relay/SSH round trip. Works even cold-launched, mirroring how
/// `ApprovalActionIntent` already reads/writes the shared DB from any process
/// context via `AppDatabase.openShared()`.
@available(iOS 17.0, *)
public struct PendingApprovalsQueryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Pending Approvals"
    public static let description = IntentDescription("Check whether any approvals are waiting for your review.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let db = try? AppDatabase.openShared(),
              let pending = try? await ApprovalRepository(db).pending()
        else {
            return .result(dialog: "Couldn't check approvals right now.")
        }
        if pending.isEmpty {
            return .result(dialog: "No approvals are waiting.")
        }
        return .result(dialog: "\(pending.count) approval\(pending.count == 1 ? "" : "s") waiting for your review.")
    }
}
#endif
