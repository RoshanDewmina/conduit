// Proactive Siri relevance — intent donations (iOS 16+) and entity relevance
// (iOS 27+). Resurrected for I1 from the parked `cursor/siri-phase2-fixes-9257`
// branch, rewired onto the current `IntentsKit` entity types (D1-D3) instead
// of that branch's now-superseded `IntentEntityCatalog`.

import AppIntents
import Foundation
import IntentsKit
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

        lastSnapshot = snapshot

        await donateIntents(for: snapshot)

#if swift(>=6.4)
        if #available(iOS 27.0, *) {
            await donateRelevantEntities(for: snapshot)
        }
#endif
    }

    func clearAll() async {
        lastSnapshot = SiriRelevanceSnapshot()
#if swift(>=6.4)
        if #available(iOS 27.0, *) {
            try? await RelevantEntities.shared.removeAllEntities()
        }
#endif
    }

    private func donateIntents(for snapshot: SiriRelevanceSnapshot) async {
        if let approvalID = snapshot.pendingApprovalIDs.first,
           let entity = try? await ApprovalEntityQuery().entities(for: [approvalID]).first {
            let deny = DenyApprovalIntent()
            deny.approval = entity
            _ = try? await IntentDonationManager.shared.donate(intent: deny)
        }

        if snapshot.activeRunIDs.count == 1,
           let runID = snapshot.activeRunIDs.first,
           let entity = try? await RunEntityQuery().entities(for: [runID]).first {
            let pause = PauseRunIntent()
            pause.run = entity
            _ = try? await IntentDonationManager.shared.donate(intent: pause)

            let stop = StopRunIntent()
            stop.run = entity
            _ = try? await IntentDonationManager.shared.donate(intent: stop)
        }

        if let conversationID = snapshot.recentConversationID,
           let entity = try? await ConversationEntityQuery().entities(for: [conversationID]).first {
            let open = OpenConversationIntent()
            open.conversation = entity
            _ = try? await IntentDonationManager.shared.donate(intent: open)
        }

        if let machineID = snapshot.onlineMachineID,
           let entity = try? await MachineEntityQuery().entities(for: [machineID]).first {
            let start = StartAgentRunIntent()
            start.machine = entity
            _ = try? await IntentDonationManager.shared.donate(intent: start)
        }
    }

    private func removeStaleDonations(_ kinds: [String]) async {
        for kind in kinds {
            if kind.hasPrefix("denyApproval:") {
                let id = String(kind.dropFirst("denyApproval:".count))
                _ = try? await IntentDonationManager.shared.deleteDonations(
                    matching: .intentType(
                        DenyApprovalIntent.self,
                        entityIdentifier: EntityIdentifier(for: ApprovalEntity.self, identifier: id)
                    )
                )
            } else if kind.hasPrefix("pauseRun:") {
                let id = String(kind.dropFirst("pauseRun:".count))
                _ = try? await IntentDonationManager.shared.deleteDonations(
                    matching: .intentType(
                        PauseRunIntent.self,
                        entityIdentifier: EntityIdentifier(for: RunEntity.self, identifier: id)
                    )
                )
            } else if kind.hasPrefix("stopRun:") {
                let id = String(kind.dropFirst("stopRun:".count))
                _ = try? await IntentDonationManager.shared.deleteDonations(
                    matching: .intentType(
                        StopRunIntent.self,
                        entityIdentifier: EntityIdentifier(for: RunEntity.self, identifier: id)
                    )
                )
            } else if kind.hasPrefix("openConversation:") {
                let id = String(kind.dropFirst("openConversation:".count))
                _ = try? await IntentDonationManager.shared.deleteDonations(
                    matching: .intentType(
                        OpenConversationIntent.self,
                        entityIdentifier: EntityIdentifier(for: ConversationEntity.self, identifier: id)
                    )
                )
            } else if kind == "startAgentRun" {
                _ = try? await IntentDonationManager.shared.deleteDonations(
                    matching: .intentType(StartAgentRunIntent.self)
                )
            }
        }
    }

#if swift(>=6.4)
    @available(iOS 27.0, *)
    private func donateRelevantEntities(for snapshot: SiriRelevanceSnapshot) async {
        let entities = await relevantEntities(for: snapshot)

        guard !entities.isEmpty else {
            try? await RelevantEntities.shared.removeAllEntities()
            return
        }

        // Entity-bearing intent donations are the mechanism here (not a
        // general-purpose `AppEntityContext`, which is audio-only as of the
        // iOS 27 beta SDK phase-2 was built against) — same approach that
        // branch shipped and device-tested.
        for entity in entities {
            await donateRelevantEntity(entity)
        }
    }

    @available(iOS 27.0, *)
    private func relevantEntities(for snapshot: SiriRelevanceSnapshot) async -> [any AppEntity] {
        var entities: [any AppEntity] = []

        if let approvalID = snapshot.pendingApprovalIDs.first,
           let entity = try? await ApprovalEntityQuery().entities(for: [approvalID]).first {
            entities.append(entity)
        }

        if snapshot.activeRunIDs.count == 1,
           let runID = snapshot.activeRunIDs.first,
           let entity = try? await RunEntityQuery().entities(for: [runID]).first {
            entities.append(entity)
        }

        if let conversationID = snapshot.recentConversationID,
           let entity = try? await ConversationEntityQuery().entities(for: [conversationID]).first {
            entities.append(entity)
        }

        if let machineID = snapshot.onlineMachineID,
           let entity = try? await MachineEntityQuery().entities(for: [machineID]).first {
            entities.append(entity)
        }

        return entities
    }

    @available(iOS 27.0, *)
    private func donateRelevantEntity(_ entity: any AppEntity) async {
        switch entity {
        case let approval as ApprovalEntity:
            let deny = DenyApprovalIntent()
            deny.approval = approval
            _ = try? await IntentDonationManager.shared.donate(intent: deny)
        case let run as RunEntity:
            let pause = PauseRunIntent()
            pause.run = run
            _ = try? await IntentDonationManager.shared.donate(intent: pause)

            let stop = StopRunIntent()
            stop.run = run
            _ = try? await IntentDonationManager.shared.donate(intent: stop)
        case let conversation as ConversationEntity:
            let open = OpenConversationIntent()
            open.conversation = conversation
            _ = try? await IntentDonationManager.shared.donate(intent: open)
        case let machine as MachineEntity:
            let start = StartAgentRunIntent()
            start.machine = machine
            _ = try? await IntentDonationManager.shared.donate(intent: start)
        default:
            break
        }
    }
#endif
}
