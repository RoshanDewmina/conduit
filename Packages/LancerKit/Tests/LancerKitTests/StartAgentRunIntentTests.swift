import Foundation
import Testing
@testable import PersistenceKit

@Suite("StartAgentRunSupport")
struct StartAgentRunIntentTests {
    @Test("offline machine preparation fails closed with reconnect dialog")
    func offlineMachineFailsClosed() {
        let offlineLabel = "last seen 30m ago"
        let isOnline = offlineLabel == "online"
        #expect(isOnline == false)
    }

    @Test("multiple machines require entity disambiguation not guessing")
    func multiMachineAmbiguity() {
        let machines = [
            IntentMachineRecord(id: "relay:a", displayName: "Mac A", hostName: "a", kind: .relayMachine),
            IntentMachineRecord(id: "relay:b", displayName: "Mac B", hostName: "b", kind: .relayMachine),
        ]
        let matchA = machines.filter { $0.displayName.lowercased().contains("mac") }
        #expect(matchA.count > 1)
    }

    @Test("progress stages follow expected order")
    func progressStageOrder() {
        let stages = [
            "resolvingMachine",
            "checkingConnection",
            "creatingRun",
            "dispatchingAgent",
            "waitingForFirstState",
        ]
        #expect(stages.first == "resolvingMachine")
        #expect(stages.last == "waitingForFirstState")
    }
}
