import AppIntents
import Foundation
import IntentsKit
import LancerCore
import NotificationsKit
import PersistenceKit
import SessionFeature

// Lives in the `Lancer` app target, NOT SessionFeature (a linked SPM library) —
// same reasoning as LancerAppShortcuts.swift: `LancerLiveActivityWidget` (the
// widget extension) also links SessionFeature directly (for ApprovalActionIntent,
// which its own UI legitimately needs), and having the SAME AppIntent type
// compiled into two separate binaries (main app + extension) confuses the
// system's execution-time AppIntents lookup — confirmed live via the unified
// log: "Unable to run App Shortcut: Couldn't find AppShortcutsProvider" even
// though static discovery (the Shortcuts app listing, compiled Metadata.appintents)
// worked correctly. Static discovery and runtime execution are two different
// lookups; only the latter breaks under dual-target compilation.

/// "How many agents are running on Lancer?" — read-only, no in-app approval or
/// mutation. Routes through `CommandGateway.execute(.queryStatus)`, which tries
/// the attached SSH channel then the relay bridge; if neither is live (app never
/// connected this launch, e.g. Siri invoked while the app was fully closed), the
/// intent reports that rather than hanging — see `CommandGateway`'s doc comment.
/// Naming a `machine` (D3) speaks that machine's detail from `MachineEntity` —
/// deliberately its connection freshness, not a run count: the status snapshot
/// comes from whichever transport happens to be live and can't be attributed to
/// a specific named host, and Siri must not present stale/other-host data as
/// that machine's live state.
@available(iOS 17.0, *)
public struct AgentStatusQueryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Agent Status"
    public static let description = IntentDescription("Check how many agent runs are active right now, or ask about a specific machine.")

    @Parameter(title: "Machine")
    public var machine: MachineEntity?

    public init() {}
    public init(machine: MachineEntity? = nil) {
        self.machine = machine
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        if let machine {
            return .result(dialog: Self.machineDetailDialog(machine))
        }
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
            let machines = (try? await MachineEntityQuery().suggestedEntities()) ?? []
            if machines.isEmpty {
                return .result(dialog: "No machines are paired with Lancer yet. Open the app to connect one.")
            }
            return .result(dialog: "Lancer isn't connected to a machine right now. Open the app to reconnect.")
        }
    }

    static func machineDetailDialog(_ machine: MachineEntity) -> IntentDialog {
        guard let lastConnected = machine.lastConnectedAt else {
            return IntentDialog("\(machine.name) (\(machine.hostname)) has never connected from this phone. Open Lancer to connect.")
        }
        let relative = RelativeDateTimeFormatter().localizedString(for: lastConnected, relativeTo: .now)
        return IntentDialog("\(machine.name) (\(machine.hostname)) last connected \(relative). Open Lancer for live status.")
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

// MARK: - Read-only navigation/search intents (D3)

/// "Search Lancer for X" — read-only over the same FTS index the in-app search
/// overlay queries (`chat_fts` via `ChatConversationRepository.search`, reached
/// here through `ConversationEntityQuery`). Opens the app; the spoken result
/// summarizes what the search found so the answer is useful hands-free too.
@available(iOS 17.0, *)
public struct SearchLancerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Search Lancer"
    public static let description = IntentDescription("Search your agent conversations.")
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Query", requestValueDialog: "What do you want to search for?")
    public var query: String

    public init() {}
    public init(query: String) {
        self.query = query
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let matches = try await ConversationEntityQuery().entities(matching: query)
        // `openAppWhenRun` brings Lancer to the foreground; without this the
        // app just opened to whatever screen was already showing rather than
        // the search the spoken result is describing (SiriNavigation, I2).
        SiriNavigationDispatch.post(SiriNavigationPayload(action: .search, searchQuery: query))
        if matches.isEmpty {
            return .result(dialog: "No conversations match '\(query)'.")
        }
        let top = matches[0]
        if matches.count == 1 {
            return .result(dialog: "One conversation matches '\(query)': '\(top.title)' on \(top.hostName).")
        }
        return .result(dialog: "\(matches.count) conversations match '\(query)' — most recent: '\(top.title)' on \(top.hostName).")
    }
}

/// "Open <conversation> in Lancer" — the entity parameter gives search +
/// disambiguation for free (`ConversationEntityQuery` string-matches over FTS;
/// multiple hits → system picker). Read-only: opens the app, never dispatches.
@available(iOS 17.0, *)
public struct OpenConversationIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Conversation"
    public static let description = IntentDescription("Open one of your agent conversations.")
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Conversation", requestValueDialog: "Which conversation?")
    public var conversation: ConversationEntity

    public init() {}
    public init(conversation: ConversationEntity) {
        self.conversation = conversation
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        // Same gap as `SearchLancerIntent` — `openAppWhenRun` opens Lancer but
        // previously left navigation entirely up to whatever screen was
        // already showing (SiriNavigation, I2).
        SiriNavigationDispatch.post(SiriNavigationPayload(action: .openConversation, conversationId: conversation.id))
        return .result(dialog: "Opening '\(conversation.title)' from \(conversation.hostName).")
    }
}
