import AppIntents
import Foundation
import NotificationsKit
import SessionFeature

#if os(iOS)
import UIKit

/// Wires iOS 27 Spotlight indexing and relevance donations from AppFeature signals.
@available(iOS 17.0, *)
enum SiriSurfaceBootstrap {
    static func install() {
        NotificationCenter.default.addObserver(
            forName: .lancerSiriSurfaceRefresh,
            object: nil,
            queue: .main
        ) { _ in
            Task { await refreshFromCurrentState() }
        }
    }

    static func refreshOnLaunch() {
        Task {
            if #available(iOS 18.0, *) {
                await SiriEntityIndexer.shared.refreshAll()
            }
            await refreshFromCurrentState()
        }
    }

    @MainActor
    static func refreshFromCurrentState() async {
        let pending = (try? await SiriIntentSupport.openCatalog().pendingApprovals()) ?? []
        let pendingIDs = pending.map(\.id)
        let activeRunIDs = ActiveRunRegistry.shared.activeRunIDs
        let recentConversationID = UserDefaults.standard.string(forKey: recentConversationDefaultsKey)

        var onlineMachineID: String?
        if let catalog = try? SiriIntentSupport.openCatalog() {
            let relay = await SiriIntentSupport.relayMachineSnapshots()
            if let machines = try? await catalog.machines(relayMachines: relay) {
                onlineMachineID = machines.first {
                    SiriIntentSupport.machineConnectivityLabel($0) == "online"
                }?.id
            }
        }

        if #available(iOS 18.0, *) {
            try? await SiriEntityIndexer.shared.refreshPendingApprovals()
            try? await SiriEntityIndexer.shared.refreshActiveRuns()
        }

        await SiriRelevanceCoordinator.shared.refresh(
            pendingApprovalIDs: pendingIDs,
            activeRunIDs: activeRunIDs,
            recentConversationID: recentConversationID,
            onlineMachineID: onlineMachineID
        )
    }

    static let recentConversationDefaultsKey = SiriSurfaceDefaultsKey.recentConversationID

    static func noteRecentConversation(id: String) {
        UserDefaults.standard.set(id, forKey: recentConversationDefaultsKey)
        NotificationCenter.default.post(name: .lancerSiriSurfaceRefresh, object: nil)
    }
}
#endif
