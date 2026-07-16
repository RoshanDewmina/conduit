#if os(iOS)
import Foundation
import Observation
import SessionFeature

/// Presentation coordinator for Orca-style daemon-owned terminals over relay.
@MainActor @Observable
public final class TerminalSessionCoordinator {
    public private(set) var presentedModel: RelayTerminalModel?
    public var lastErrorMessage: String?

    private let relayFleetStore: RelayFleetStore

    public init(relayFleetStore: RelayFleetStore) {
        self.relayFleetStore = relayFleetStore
    }

    public func openTerminal(
        on machine: RelayFleetStore.Machine,
        cwd: String? = nil,
        startupCommand: String? = nil
    ) {
        lastErrorMessage = nil
        guard relayFleetStore.isConnected(machine.id) else {
            lastErrorMessage = "Machine is not connected over relay."
            return
        }
        presentedModel = RelayTerminalModel(
            bridge: machine.bridge,
            title: machine.record.displayName,
            cwd: cwd,
            startupCommand: startupCommand
        )
    }

    public func openOnFirstConnectedMachine(cwd: String? = nil, startupCommand: String? = nil) {
        guard let machine = relayFleetStore.firstConnectedMachine else {
            lastErrorMessage = "No connected machine. Pair one in Trusted Machines."
            return
        }
        openTerminal(on: machine, cwd: cwd, startupCommand: startupCommand)
    }

    public func dismissTerminal() {
        presentedModel?.stop()
        presentedModel = nil
    }

    /// DEBUG / harness: open terminal on first connected relay machine.
    public func openFirstHostIfAvailable() async {
        openOnFirstConnectedMachine()
    }
}
#endif
