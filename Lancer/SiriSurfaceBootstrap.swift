import AppIntents
import Foundation
import IntentsKit
import NotificationsKit
import PersistenceKit
import SessionFeature

/// Wires Siri relevance donations (Phase 2, resurrected in I1) and Spotlight
/// entity indexing (I2) from a small set of app-lifecycle signals.
/// Deliberately does NOT reach into `AppRoot`'s reactive state directly (fleet
/// slots view model, `CursorAppShell` navigation) — that would mean editing
/// the large, heavily-tested `AppRoot.swift`/shell files for a
/// proactive-surfacing nicety, which was out of scope for I1 and stays out of
/// scope here.
///
/// Milestone 1 ("wire what already exists") closes the cadence gap I1 left
/// open: instead of refreshing only at launch, this also observes the
/// existing `NotificationCenter` signals that already fire today from real
/// state changes — relay message handling (`E2ERelayBridge.handleRelayMessage`),
/// the local-SSH approval/run ingest path (`ApprovalIngest`), conversation
/// persistence (`ChatConversationRepository`/`ApprovalIngest.postThreadArtifactUpdate`),
/// and Siri's own open-conversation navigation (`SiriNavigationDispatch`).
/// None of these notifications are new or repurposed for this — they already
/// existed and already fired; this only adds a listener so relevance
/// donations + Spotlight indexing stay fresh without requiring a relaunch or
/// a manual `.lancerSiriSurfaceRefresh` post.
@available(iOS 17.0, *)
enum SiriSurfaceBootstrap {
    static let surfaceRefreshNotification = Notification.Name("dev.lancer.siriSurfaceRefresh")

    /// Real state-change signals mapped to the roadmap's M1 list:
    /// - relay connect / online status → `lancerE2EStatusUpdate`
    /// - pending approval → `lancerE2EApprovalReceived` / `lancerE2EApprovalResolved`
    /// - run start/end → `lancerE2ERunStatus` / `lancerE2ELiveRunStatus`
    /// - pending question (feeds phrase 9's freshness too) → `lancerE2EQuestionPending`
    /// - conversation open/activity → `lancerChatArtifactPersisted` (content
    ///   persisted, fired by both the local-SSH and relay ingest paths) and
    ///   `.lancerSiriNavigation` (Siri itself opened a conversation).
    ///
    /// Named by raw string (not the typed `Notification.Name` constants
    /// declared in `AppFeature`/`SessionFeature`) because those extensions are
    /// internal to their own modules — the same reason `ApprovalIngest.swift`
    /// and `E2ERelayBridge.swift` post with raw string literals themselves.
    private static let stateChangeNotificationNames: [Notification.Name] = [
        Notification.Name("lancerE2EApprovalReceived"),
        Notification.Name("lancerE2EApprovalResolved"),
        Notification.Name("lancerE2EStatusUpdate"),
        Notification.Name("lancerE2ERunStatus"),
        Notification.Name("lancerE2ELiveRunStatus"),
        Notification.Name("lancerE2EQuestionPending"),
        Notification.Name("lancerChatArtifactPersisted"),
    ]

    static func install() {
        NotificationCenter.default.addObserver(
            forName: surfaceRefreshNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { await refreshFromCurrentState() }
        }

        for name in stateChangeNotificationNames {
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { _ in
                Task { await refreshFromCurrentState() }
            }
        }

        // Siri opening a conversation is itself a "conversation open" signal —
        // refresh so the next phrase (e.g. a follow-up "search" or "open")
        // sees this conversation as the most recent one.
        NotificationCenter.default.addObserver(
            forName: .lancerSiriNavigation,
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

        // Spotlight indexing (I2) needs iOS 18's `IndexedEntity`; on iOS 17
        // devices this refresh cadence still runs relevance donations above,
        // just without the Spotlight side.
        if #available(iOS 18.0, *) {
            await SiriEntityIndexer.shared.refreshAll()
        }
    }
}
