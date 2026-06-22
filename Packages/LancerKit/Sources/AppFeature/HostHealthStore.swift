#if os(iOS)
import Foundation
import Observation
import LancerCore
import SSHTransport

@MainActor @Observable
public final class HostHealthStore {
    public var healthByHost: [HostID: HostHealth] = [:]
    public var lastRefresh: Date?

    private var pollTask: Task<Void, Never>?
    private let interval: TimeInterval

    public init(interval: TimeInterval = 60) {
        self.interval = interval
    }

    public func startPolling(fleetStore: FleetStore) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh(fleetStore: fleetStore)
                try? await Task.sleep(for: .seconds(self.interval))
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func refresh(fleetStore: FleetStore) async {
        for slot in fleetStore.slots {
            guard slot.sessionViewModel.status == .connected else { continue }
            if let health = try? await slot.channel.getHostHealth() {
                healthByHost[slot.hostID] = health
            }
        }
        lastRefresh = Date()
    }

    public func health(for hostID: HostID) -> HostHealth? {
        healthByHost[hostID]
    }
}
#endif
