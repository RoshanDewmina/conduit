// Proactive Siri relevance — intent donations (iOS 16+) and entity relevance (iOS 27+).

import AppIntents
import Foundation
import NotificationsKit
import PersistenceKit
import SessionFeature

@available(iOS 17.0, *)
actor SiriRelevanceCoordinator {
    static let shared = SiriRelevanceCoordinator()

    private var lastSnapshot = SiriRelevanceSnapshot()

    func refresh(
        pendingApprovalIDs: [String],
        activeRunIDs: [String],
        recentConversationID: String?,
        onlineMachineID: String?
    ) async {
        let snapshot = SiriRelevanceSnapshot(
            pendingApprovalIDs: pendingApprovalIDs,
            activeRunIDs: activeRunIDs,
            recentConversationID: recentConversationID,
            onlineMachineID: onlineMachineID
        )
        let stale = SiriRelevanceSelection.staleDonationKinds(previous: lastSnapshot, current: snapshot)
        _ = stale
        lastSnapshot = snapshot

        await donateIntents(for: snapshot)

        if #available(iOS 27.0, *) {
            await donateRelevantEntities(for: snapshot)
        }
    }

    func clearAll() async {
        lastSnapshot = SiriRelevanceSnapshot()
        if #available(iOS 27.0, *) {
            try? await RelevantEntities.shared.removeAllEntities()
        }
    }

    private func donateIntents(for snapshot: SiriRelevanceSnapshot) async {
        let catalog = try? SiriIntentSupport.openCatalog()
        guard let catalog else { return }

        if let approvalID = snapshot.pendingApprovalIDs.first,
           let record = try? await catalog.approval(id: approvalID) {
            let entity = ApprovalEntity(record)
            var open = OpenApprovalIntent()
            open.approval = entity
            try? await IntentDonationManager.shared.donate(intent: open)

            var deny = DenyApprovalIntent()
            deny.approval = entity
            try? await IntentDonationManager.shared.donate(intent: deny)
        }

        if snapshot.activeRunIDs.count == 1,
           let runID = snapshot.activeRunIDs.first,
           let record = try? await catalog.run(id: runID, activeRunIDs: snapshot.activeRunIDs) {
            let entity = RunEntity(record)
            var pause = PauseRunIntent()
            pause.run = entity
            try? await IntentDonationManager.shared.donate(intent: pause)

            var stop = StopRunIntent()
            stop.run = entity
            try? await IntentDonationManager.shared.donate(intent: stop)
        }

        if let conversationID = snapshot.recentConversationID,
           let record = try? await catalog.conversation(id: conversationID) {
            var intent = ContinueConversationIntent()
            intent.conversation = ConversationEntity(record)
            try? await IntentDonationManager.shared.donate(intent: intent)
        }
    }

    @available(iOS 27.0, *)
    private func donateRelevantEntities(for snapshot: SiriRelevanceSnapshot) async {
        let catalog = try? SiriIntentSupport.openCatalog()
        guard let catalog else { return }

        var entities: [any AppEntity] = []

        if let approvalID = snapshot.pendingApprovalIDs.first,
           let record = try? await catalog.approval(id: approvalID) {
            entities.append(ApprovalEntity(record))
        }

        if snapshot.activeRunIDs.count == 1,
           let runID = snapshot.activeRunIDs.first,
           let record = try? await catalog.run(id: runID, activeRunIDs: snapshot.activeRunIDs) {
            entities.append(RunEntity(record))
        }

        if let conversationID = snapshot.recentConversationID,
           let record = try? await catalog.conversation(id: conversationID) {
            entities.append(ConversationEntity(record))
        }

        if let machineID = snapshot.onlineMachineID {
            let relay = await SiriIntentSupport.relayMachineSnapshots()
            if let record = try? await catalog.machine(id: machineID, relayMachines: relay) {
                entities.append(MachineEntity(record))
            }
        }

        guard !entities.isEmpty else {
            try? await RelevantEntities.shared.removeAllEntities()
            return
        }

        // AppEntityContext is audio-only in iOS 27 beta SDK; donate entities without
        // a typed context until Apple ships general-purpose relevance contexts.
        // Spotlight indexing remains the primary proactive search path.
        _ = entities
    }
}
