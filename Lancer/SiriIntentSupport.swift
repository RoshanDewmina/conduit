import AppIntents
import Foundation
import LancerCore
import NotificationsKit
import PersistenceKit
import SessionFeature
import SSHTransport

// Shared helpers for Lancer App Intents in the app target (not SessionFeature).

@available(iOS 17.0, *)
enum SiriIntentSupport {
    static func openCatalog() throws -> IntentEntityCatalog {
        guard let db = try? AppDatabase.openShared() else {
            throw SiriIntentError.databaseUnavailable
        }
        return IntentEntityCatalog(db)
    }

    @MainActor
    static func activeRunIDs() -> [String] {
        ActiveRunRegistry.shared.activeRunIDs
    }

    static func relayMachineSnapshots() async -> [IntentRelayMachineSnapshot] {
        await RelayMachineMigration.readIndex().map {
            IntentRelayMachineSnapshot(
                id: $0.id.uuidString,
                displayName: $0.displayName,
                lastConnectedAt: $0.lastConnectedAt
            )
        }
    }

    static func postNavigation(
        _ action: SiriNavigationAction,
        conversationId: String? = nil,
        machineId: String? = nil,
        approvalId: String? = nil,
        searchQuery: String? = nil
    ) {
        let payload = SiriNavigationPayload(
            action: action,
            conversationId: conversationId,
            machineId: machineId,
            approvalId: approvalId,
            searchQuery: searchQuery
        )
        SiriNavigationBuffer.shared.record(payload)
        NotificationCenter.default.post(
            name: .lancerSiriNavigation,
            object: nil,
            userInfo: payload.userInfo
        )
    }

    static func machineConnectivityLabel(_ machine: IntentMachineRecord) -> String {
        guard let last = machine.lastConnectedAt else { return "offline" }
        if last.timeIntervalSinceNow > -600 { return "online" }
        let minutes = max(1, Int(-last.timeIntervalSinceNow / 60))
        return "last seen \(minutes)m ago"
    }

    static func runDialogSubject(_ run: IntentRunRecord) -> String {
        if let host = run.hostName, let conv = run.conversationTitle {
            return "\(conv) on \(host)"
        }
        return run.title
    }

    static func approvalDialogSubject(_ approval: IntentApprovalRecord) -> String {
        var parts = [approval.headline]
        if !approval.workspacePath.isEmpty {
            parts.append("in \(URL(fileURLWithPath: approval.workspacePath).lastPathComponent)")
        }
        parts.append(approval.riskLabel)
        return parts.joined(separator: " · ")
    }

    static func conversationDialogSubject(_ conversation: IntentConversationRecord) -> String {
        "\(conversation.title) on \(conversation.hostName)"
    }

    static func relayMachineUUID(from machineRecordID: String) -> String? {
        if machineRecordID.hasPrefix("relay:") {
            return String(machineRecordID.dropFirst("relay:".count))
        }
        return UUID(uuidString: machineRecordID).map(\.uuidString)
    }

    static func promptExcerpt(_ prompt: String, maxLength: Int = 80) -> String {
        if prompt.count <= maxLength { return prompt }
        return String(prompt.prefix(maxLength)) + "…"
    }
}

enum SiriIntentError: Error, CustomLocalizedStringResourceConvertible {
    case databaseUnavailable
    case entityNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .databaseUnavailable: "Couldn't open Lancer's database."
        case .entityNotFound: "That item isn't available anymore."
        }
    }
}

@available(iOS 17.0, *)
enum SiriIntentDialogs {
    static func noPairedMachines() -> IntentDialog {
        IntentDialog("No machines are paired yet. Open Lancer to connect one.")
    }

    static func transportUnavailable(machine: String?) -> IntentDialog {
        if let machine {
            return IntentDialog("\(machine) isn't connected right now. Open Lancer to reconnect.")
        }
        return IntentDialog("Lancer isn't connected to a machine right now. Open Lancer to reconnect.")
    }

    static func pauseSuccess(_ run: IntentRunRecord) -> IntentDialog {
        IntentDialog("Paused \(SiriIntentSupport.runDialogSubject(run)).")
    }

    static func stopSuccess(_ run: IntentRunRecord) -> IntentDialog {
        IntentDialog("Stopped \(SiriIntentSupport.runDialogSubject(run)).")
    }

    static func denySuccess(_ approval: IntentApprovalRecord) -> IntentDialog {
        IntentDialog("Denied \(SiriIntentSupport.approvalDialogSubject(approval)).")
    }

    static func openedConversation(_ conversation: IntentConversationRecord) -> IntentDialog {
        IntentDialog("Opened \(SiriIntentSupport.conversationDialogSubject(conversation)).")
    }

    static func continueConversation(_ conversation: IntentConversationRecord) -> IntentDialog {
        IntentDialog("Opened \(conversation.title). Type your next message in Lancer to continue — nothing was sent to the agent yet.")
    }

    static func searchResults(_ query: String, count: Int) -> IntentDialog {
        if count == 0 {
            return IntentDialog("No conversations matched \"\(query)\".")
        }
        return IntentDialog("Found \(count) conversation\(count == 1 ? "" : "s") for \"\(query)\". Open Lancer to review them.")
    }
}
