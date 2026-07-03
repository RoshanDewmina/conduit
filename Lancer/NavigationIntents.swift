import AppIntents
import Foundation

// Lives in the `Lancer` app target — see StatusQueryIntents.swift's header
// comment for why (dual-target AppIntent compilation breaks runtime execution
// lookup even though static Shortcuts discovery still works).

@available(iOS 17.0, *)
public struct SearchLancerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Search Lancer"
    public static let description = IntentDescription("Search your Lancer conversations.")
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Query")
    public var searchText: String

    public init() {}
    public init(searchText: String) { self.searchText = searchText }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "What should I search for?")
        }

        let catalog = try SiriIntentSupport.openCatalog()
        let results = try await catalog.searchConversations(trimmed)
        SiriIntentSupport.postNavigation(.search, searchQuery: trimmed)
        return .result(dialog: SiriIntentDialogs.searchResults(trimmed, count: results.count))
    }
}

@available(iOS 17.0, *)
public struct OpenConversationIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Conversation"
    public static let description = IntentDescription("Open a Lancer conversation.")
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Conversation")
    public var conversation: ConversationEntity

    public init() {}
    public init(conversation: ConversationEntity) { self.conversation = conversation }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let catalog = try SiriIntentSupport.openCatalog()
        guard let record = try await catalog.conversation(id: conversation.id) else {
            return .result(dialog: "That conversation isn't on this device anymore.")
        }
        SiriIntentSupport.postNavigation(.openConversation, conversationId: record.id)
        return .result(dialog: SiriIntentDialogs.openedConversation(record))
    }
}

@available(iOS 17.0, *)
public struct OpenMachineIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Machine"
    public static let description = IntentDescription("Open a paired machine in Lancer.")
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Machine")
    public var machine: MachineEntity

    public init() {}
    public init(machine: MachineEntity) { self.machine = machine }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let catalog = try SiriIntentSupport.openCatalog()
        let relay = await SiriIntentSupport.relayMachineSnapshots()
        guard let record = try await catalog.machine(id: machine.id, relayMachines: relay) else {
            return .result(dialog: "That machine isn't paired anymore.")
        }
        SiriIntentSupport.postNavigation(.openMachine, machineId: record.id)
        return .result(dialog: "Opened \(record.displayName) (\(SiriIntentSupport.machineConnectivityLabel(record))).")
    }
}

@available(iOS 17.0, *)
public struct OpenApprovalIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Approval"
    public static let description = IntentDescription("Open a pending approval for review in Lancer.")
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Approval")
    public var approval: ApprovalEntity

    public init() {}
    public init(approval: ApprovalEntity) { self.approval = approval }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let catalog = try SiriIntentSupport.openCatalog()
        guard let record = try await catalog.approval(id: approval.id) else {
            return .result(dialog: "That approval was already resolved.")
        }
        SiriIntentSupport.postNavigation(.openApproval, approvalId: record.id)
        return .result(dialog: "Opened \(SiriIntentSupport.approvalDialogSubject(record)) for review. Approve in Lancer — voice can't approve commands.")
    }
}

@available(iOS 17.0, *)
public struct ContinueConversationIntent: AppIntent {
    public static let title: LocalizedStringResource = "Continue Conversation"
    public static let description = IntentDescription("Open a conversation so you can continue work in Lancer.")
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Conversation")
    public var conversation: ConversationEntity

    public init() {}
    public init(conversation: ConversationEntity) { self.conversation = conversation }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let catalog = try SiriIntentSupport.openCatalog()
        guard let record = try await catalog.conversation(id: conversation.id) else {
            return .result(dialog: "That conversation isn't on this device anymore.")
        }
        SiriIntentSupport.postNavigation(.continueConversation, conversationId: record.id)
        return .result(dialog: SiriIntentDialogs.continueConversation(record))
    }
}
