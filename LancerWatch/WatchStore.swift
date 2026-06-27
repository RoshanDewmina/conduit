import SwiftUI
import WatchKit
import WidgetKit
import LancerCore

private let appGroupID = "group.dev.lancer.mobile"
private let pendingCountKey = "watchPendingCount"

@MainActor @Observable
final class WatchStore {
    // Inbox
    var approvals: [WatchApprovalTransfer] = []
    // Session
    var sessionStatus: WatchSessionStatus?
    // Activity feed
    var recentActivity: [WatchActivityBlock] = []
    // Snippets
    var snippets: [WatchSnippet] = []
    // UI state
    var isStopping: Bool = false
    var lastRunSnippetID: String?

    let connector: WatchConnector
    @ObservationIgnored nonisolated(unsafe) private var consumeTask: Task<Void, Never>?

    init(connector: WatchConnector) {
        self.connector = connector
    }

    func start() {
        connector.activate()
        consumeTask?.cancel()
        consumeTask = Task { [weak self] in
            guard let self else { return }
            for await message in connector.messages {
                guard !Task.isCancelled else { break }
                switch message {
                case .approvalSync(let items):
                    self.approvals = items
                    self.updateComplication(pendingCount: items.count)
                case .sessionSync(let status):
                    self.sessionStatus = status
                    if !status.isConnected { self.isStopping = false }
                case .activitySync(let blocks):
                    self.recentActivity = blocks
                case .snippetSync(let items):
                    self.snippets = items
                default:
                    break  // decision/emergencyStop/runSnippet are Watch→iPhone only
                }
            }
        }
    }

    // MARK: - Actions

    func decideApproval(_ item: WatchApprovalTransfer, approved: Bool) {
        WKInterfaceDevice.current().play(approved ? .success : .failure)
        connector.sendDecision(approvalID: item.id, result: approved ? "approved" : "rejected")
        approvals.removeAll { $0.id == item.id }
        updateComplication(pendingCount: approvals.count)
    }

    func emergencyStop() {
        isStopping = true
        WKInterfaceDevice.current().play(.failure)
        connector.sendEmergencyStop()
    }

    func runSnippet(_ snippet: WatchSnippet) {
        WKInterfaceDevice.current().play(.click)
        lastRunSnippetID = snippet.id
        connector.sendRunSnippet(body: snippet.body)
    }

    // MARK: - Complication

    private func updateComplication(pendingCount: Int) {
        UserDefaults(suiteName: appGroupID)?.set(pendingCount, forKey: pendingCountKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    deinit {
        consumeTask?.cancel()
    }
}
