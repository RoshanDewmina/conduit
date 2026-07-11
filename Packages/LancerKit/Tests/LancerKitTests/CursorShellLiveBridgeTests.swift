#if os(iOS)
import Testing
@testable import AppFeature

@Suite("CursorShellLiveBridge")
struct CursorShellLiveBridgeTests {

    /// Two conversations with the same repo name but different hostIDs must
    /// aggregate into a single WorkspaceRow with two distinct RunTargets —
    /// proving the host-collision case described in ADR §1 is resolved.
    @Test("same repo, two hostIDs → one WorkspaceRow with two RunTargets")
    @MainActor
    func twoHostsSameRepo() {
        let bridge = CursorShellLiveBridge()

        let runTargets: [CursorShellLiveBridge.RunTarget] = [
            CursorShellLiveBridge.RunTarget(machineID: "host-aaa", hostName: "hermes-box"),
            CursorShellLiveBridge.RunTarget(machineID: "host-bbb", hostName: "studio-m4"),
        ]

        bridge.reloadWorkspaces(
            from: ["command-center"],
            threadCounts: ["command-center": 2],
            runTargetsByRepo: ["command-center": runTargets]
        )

        #expect(bridge.workspaces.count == 1)
        let row = bridge.workspaces[0]
        #expect(row.name == "command-center")
        #expect(row.threadCount == 2)
        #expect(row.runTargets.count == 2)
        #expect(Set(row.runTargets.map(\.machineID)) == Set(["host-aaa", "host-bbb"]))
        #expect(Set(row.runTargets.map(\.hostName)) == Set(["hermes-box", "studio-m4"]))
    }

    @Test("single hostID → one RunTarget, hostName surfaced")
    @MainActor
    func singleHostRepo() {
        let bridge = CursorShellLiveBridge()

        bridge.reloadWorkspaces(
            from: ["lancer-ios"],
            threadCounts: ["lancer-ios": 5],
            runTargetsByRepo: ["lancer-ios": [
                CursorShellLiveBridge.RunTarget(machineID: "host-ccc", hostName: "dev-macbook"),
            ]]
        )

        #expect(bridge.workspaces.count == 1)
        let row = bridge.workspaces[0]
        #expect(row.runTargets.count == 1)
        #expect(row.runTargets[0].hostName == "dev-macbook")
        #expect(row.runTargets[0].machineID == "host-ccc")
    }

    @Test("no hostIDs → empty runTargets (backward compat)")
    @MainActor
    func noHostIDs() {
        let bridge = CursorShellLiveBridge()

        bridge.reloadWorkspaces(
            from: ["old-repo"],
            threadCounts: ["old-repo": 3]
        )

        #expect(bridge.workspaces.count == 1)
        #expect(bridge.workspaces[0].runTargets.isEmpty)
    }

    @Test("ThreadRow carries hostID and hostName")
    @MainActor
    func threadRowHostFields() {
        let row = CursorShellLiveBridge.ThreadRow(
            id: "t1",
            title: "Add login flow",
            repoName: "command-center",
            updatedAt: nil,
            hostID: "host-aaa",
            hostName: "hermes-box"
        )
        #expect(row.hostID == "host-aaa")
        #expect(row.hostName == "hermes-box")
    }

    @Test("selectedRunTargetMachineID persists on bridge")
    @MainActor
    func selectedRunTargetPersistence() {
        let bridge = CursorShellLiveBridge()
        bridge.selectedRunTargetMachineID = "host-bbb"
        bridge.selectedRunTargetHostName = "studio-m4"
        #expect(bridge.selectedRunTargetMachineID == "host-bbb")
        #expect(bridge.selectedRunTargetHostName == "studio-m4")
    }
}
#endif
