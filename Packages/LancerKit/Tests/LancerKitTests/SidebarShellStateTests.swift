import Testing
@testable import AppFeature

@Suite("SidebarShellState")
@MainActor
struct SidebarShellStateTests {
    @Test("Command Home is the default destination")
    func defaultDestinationIsHome() {
        let state = SidebarShellState()

        #expect(state.selectedDestination == .home)
        #expect(state.previousDestination == nil)
    }

    @Test("Machine presentation preserves Home as the back destination")
    func machineNavigationRecordsHome() {
        let state = SidebarShellState()
        state.isDrawerOpen = true

        state.navigate(to: .machines)

        #expect(state.selectedDestination == .machines)
        #expect(state.previousDestination == .home)
        #expect(state.isDrawerOpen == false)
    }

    @Test("Returning from settings restores the selected destination")
    func returnToPreviousDestination() {
        let state = SidebarShellState()
        state.navigate(to: .machines)
        state.navigate(to: .settings)

        state.returnToPreviousDestination()

        #expect(state.selectedDestination == .machines)
    }
}
