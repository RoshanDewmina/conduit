import AppIntents
import Foundation
import IntentsKit
import PersistenceKit
import SessionFeature

/// Wires Siri relevance donations (Phase 2, resurrected in I1) from a small
/// set of app-lifecycle signals. Deliberately does NOT reach into `AppRoot`'s
/// reactive state (fleet slots, relay bridges opening/closing, new
/// conversations) — that would mean editing the large, heavily-tested
/// `AppRoot.swift` for a proactive-surfacing nicety, which is out of scope for
/// I1. Instead this refreshes once at launch and whenever
/// `.lancerSiriSurfaceRefresh` is posted (callers opt in by posting that
/// notification; nothing currently does, so this is inert until wired — the
/// donation *logic* is real and unit-tested, the trigger cadence is the
/// intentionally-deferred part).
@available(iOS 17.0, *)
enum SiriSurfaceBootstrap {
    static let surfaceRefreshNotification = Notification.Name("dev.lancer.siriSurfaceRefresh")

    static func install() {
        NotificationCenter.default.addObserver(
            forName: surfaceRefreshNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { await refreshFromCurrentState() }
        }
    }

    static func refreshOnLaunch() {
        Task { await refreshFromCurrentState() }
    }

    @MainActor
    static func refreshFromCurrentState() async {
        guard let db = try? IntentsKitDependencies.database() else { return }

        let pendingIDs = ((try? await ApprovalRepository(db).pending()) ?? []).map(\.id.uuidString)
        let activeRunIDs = ActiveRunRegistry.shared.activeRunIDs
        let recentConversations = (try? await ChatConversationRepository(db).recent(limit: 1)) ?? []
        let recentConversationID = recentConversations.first?.id

        var onlineMachineID: String?
        let relayMachines = await IntentsKitDependencies.relayMachineSnapshots()
        for machine in relayMachines {
            let recentlyConnected = machine.lastConnectedAt.map { $0.timeIntervalSinceNow > -600 } ?? false
            let bridgeActive = ApprovalRelay.shared.relayBridges[machine.id]?.isActive == true
            if recentlyConnected || bridgeActive {
                onlineMachineID = "relay:\(machine.id.uuidString)"
                break
            }
        }

        await SiriRelevanceCoordinator.shared.refresh(
            pendingApprovalIDs: pendingIDs,
            activeRunIDs: activeRunIDs,
            recentConversationID: recentConversationID,
            onlineMachineID: onlineMachineID
        )
    }
}
