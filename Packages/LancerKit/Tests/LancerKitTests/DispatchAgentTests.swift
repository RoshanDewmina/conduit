#if os(iOS)
import Testing
@testable import AppFeature

@Suite("DispatchAgent")
struct DispatchAgentTests {

    @Test("preferredAgentID prefers online agent on selected machine")
    func prefersOnlineOnSelectedMachine() {
        let agents = [
            DispatchAgent(id: "slot-a|claudeCode", name: "Claude", cwd: "~", isOffline: false, hostID: "host-a", hostName: "Mac A"),
            DispatchAgent(id: "slot-b|claudeCode", name: "Claude", cwd: "~", isOffline: false, hostID: "host-b", hostName: "Mac B"),
        ]
        let id = DispatchAgent.preferredAgentID(from: agents, preferredMachineID: "host-b")
        #expect(id == "slot-b|claudeCode")
    }

    @Test("preferredAgentID falls back to offline agent on selected machine")
    func fallsBackToOfflineOnSelectedMachine() {
        let agents = [
            DispatchAgent(id: "slot-a|claudeCode", name: "Claude", cwd: "~", isOffline: false, hostID: "host-a", hostName: "Mac A"),
            DispatchAgent(id: "slot-b|claudeCode", name: "Claude", cwd: "~", isOffline: true, hostID: "host-b", hostName: "Mac B"),
        ]
        let id = DispatchAgent.preferredAgentID(from: agents, preferredMachineID: "host-b")
        #expect(id == "slot-b|claudeCode")
    }

    @Test("preferredAgentID ignores stale machine and picks first online")
    func ignoresStaleMachineSelection() {
        let agents = [
            DispatchAgent(id: "slot-a|claudeCode", name: "Claude", cwd: "~", isOffline: false, hostID: "host-a", hostName: "Mac A"),
        ]
        let id = DispatchAgent.preferredAgentID(from: agents, preferredMachineID: "missing-host")
        #expect(id == "slot-a|claudeCode")
    }
}
#endif
