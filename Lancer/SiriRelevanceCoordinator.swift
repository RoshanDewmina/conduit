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
        await removeStaleDonations(stale)

        if #available(iOS 27.0, *) {
            await syncRelevantEntities(previous: lastSnapshot, current: snapshot)
        }

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

        if let machineID = snapshot.onlineMachineID {
            let relay = await SiriIntentSupport.relayMachineSnapshots()
            if let record = try? await catalog.machine(id: machineID, relayMachines: relay) {
                var start = StartAgentRunIntent()
                start.machine = MachineEntity(record)
                try? await IntentDonationManager.shared.donate(intent: start)
            }
        }
    }

    private func removeStaleDonations(_ kinds: [String]) async {
        for kind in kinds {
            if kind.hasPrefix("openApproval:") {
                let id = String(kind.dropFirst("openApproval:".count))
                try? await IntentDonationManager.shared.deleteDonations(
                    matching: .intentType(
                        OpenApprovalIntent.self,
                        entityIdentifier: EntityIdentifier(for: ApprovalEntity.self, identifier: id)
                    )
                )
            } else if kind.hasPrefix("denyApproval:") {
                let id = String(kind.dropFirst("denyApproval:".count))
                try? await IntentDonationManager.shared.deleteDonations(
                    matching: .intentType(
                        DenyApprovalIntent.self,
                        entityIdentifier: EntityIdentifier(for: ApprovalEntity.self, identifier: id)
                    )
                )
            } else if kind.hasPrefix("pauseRun:") {
                let id = String(kind.dropFirst("pauseRun:".count))
                try? await IntentDonationManager.shared.deleteDonations(
                    matching: .intentType(
                        PauseRunIntent.self,
                        entityIdentifier: EntityIdentifier(for: RunEntity.self, identifier: id)
                    )
                )
            } else if kind.hasPrefix("stopRun:") {
                let id = String(kind.dropFirst("stopRun:".count))
                try? await IntentDonationManager.shared.deleteDonations(
                    matching: .intentType(
                        StopRunIntent.self,
                        entityIdentifier: EntityIdentifier(for: RunEntity.self, identifier: id)
                    )
                )
            } else if kind.hasPrefix("continueConversation:") {
                let id = String(kind.dropFirst("continueConversation:".count))
                try? await IntentDonationManager.shared.deleteDonations(
                    matching: .intentType(
                        ContinueConversationIntent.self,
                        entityIdentifier: EntityIdentifier(for: ConversationEntity.self, identifier: id)
                    )
                )
            } else if kind == "startAgentRun" {
                try? await IntentDonationManager.shared.deleteDonations(
                    matching: .intentType(StartAgentRunIntent.self)
                )
            }
        }
    }

    @available(iOS 27.0, *)
    private func donateRelevantEntities(for snapshot: SiriRelevanceSnapshot) async {
        let catalog = try? SiriIntentSupport.openCatalog()
        guard let catalog else { return }

        let entities = await relevantEntities(for: snapshot, catalog: catalog)

        guard !entities.isEmpty else {
            try? await RelevantEntities.shared.removeAllEntities()
            return
        }

        // AppEntityContext is audio-only in iOS 27 beta SDK; register relevance via
        // entity-bearing intent donations until general-purpose contexts ship.
        // Spotlight indexing remains the primary proactive search path.
        for entity in entities {
            await donateRelevantEntity(entity)
        }
    }

    @available(iOS 27.0, *)
    private func syncRelevantEntities(
        previous: SiriRelevanceSnapshot,
        current: SiriRelevanceSnapshot
    ) async {
        let catalog = try? SiriIntentSupport.openCatalog()
        guard let catalog else { return }

        let previousEntities = await relevantEntities(for: previous, catalog: catalog)
        let currentEntities = await relevantEntities(for: current, catalog: catalog)
        let currentIDs = Set(currentEntities.map(\.id))
        let staleEntities = previousEntities.filter { !currentIDs.contains($0.id) }
        guard !staleEntities.isEmpty else { return }
        try? await RelevantEntities.shared.removeEntities(staleEntities)
    }

    @available(iOS 27.0, *)
    private func relevantEntities(
        for snapshot: SiriRelevanceSnapshot,
        catalog: IntentEntityCatalog
    ) async -> [any AppEntity] {
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

        return entities
    }

    @available(iOS 27.0, *)
    private func donateRelevantEntity(_ entity: any AppEntity) async {
        switch entity {
        case let approval as ApprovalEntity:
            var open = OpenApprovalIntent()
            open.approval = approval
            try? await IntentDonationManager.shared.donate(intent: open)

            var deny = DenyApprovalIntent()
            deny.approval = approval
            try? await IntentDonationManager.shared.donate(intent: deny)
        case let run as RunEntity:
            var pause = PauseRunIntent()
            pause.run = run
            try? await IntentDonationManager.shared.donate(intent: pause)

            var stop = StopRunIntent()
            stop.run = run
            try? await IntentDonationManager.shared.donate(intent: stop)
        case let conversation as ConversationEntity:
            var intent = ContinueConversationIntent()
            intent.conversation = conversation
            try? await IntentDonationManager.shared.donate(intent: intent)
        case let machine as MachineEntity:
            var start = StartAgentRunIntent()
            start.machine = machine
            try? await IntentDonationManager.shared.donate(intent: start)
        default:
            break
        }
    }
}
