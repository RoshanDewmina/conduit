import SwiftUI
import WatchKit
import ConduitCore

@MainActor @Observable
final class WatchInboxViewModel {
    var approvals: [WatchApprovalTransfer] = []
    var isConnected: Bool = false

    private let connector: WatchConnector
    // nonisolated(unsafe): Task.cancel() is thread-safe; deinit may run off main actor
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
                    self.isConnected = true
                case .decision:
                    break  // decisions flow Watch → iPhone only; ignore here
                }
            }
        }
    }

    func decide(_ item: WatchApprovalTransfer, approved: Bool) {
        WKInterfaceDevice.current().play(approved ? .success : .failure)
        connector.sendDecision(approvalID: item.id, result: approved ? "approved" : "rejected")
        approvals.removeAll { $0.id == item.id }
    }

    deinit {
        consumeTask?.cancel()
    }
}
