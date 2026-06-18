import Foundation
import ConduitCore
import SSHTransport

/// Listens to `DaemonChannel` events and calls `onPatch` when a patch is
/// proposed by an agent. Today only `approvalPending` and `pong` events exist;
/// future `patchProposed` events will be handled here once the daemon protocol
/// adds the corresponding case to `DaemonEvent`.
public actor RecentPatch {
    private let channel: DaemonChannel
    /// Called on `MainActor` with the unified-diff string when a patch arrives.
    private let onPatch: @Sendable (String) async -> Void
    private var task: Task<Void, Never>?

    public init(
        channel: DaemonChannel,
        onPatch: @escaping @Sendable (String) async -> Void
    ) {
        self.channel = channel
        self.onPatch = onPatch
    }

    /// Starts consuming `DaemonChannel.events` in a background `Task`.
    public func start() {
        task = Task { [channel, onPatch] in
            for await event in await channel.events {
                switch event {
                case .approvalPending(let params):
                    // Forward patch-type approvals so the diff sheet can be
                    // shown directly from a patch approval event.
                    if params.approvalKind == .patch, let patch = params.patch {
                        await onPatch(patch)
                    }
                case .pong, .agentStatus, .secretRequest, .runOutput, .runStatus, .sessionDiscovered:
                    break
                case .toolStart:
                    break
                case .unknown:
                    // Future: when DaemonEvent gains a .patchProposed case,
                    // decode and forward the unified diff here.
                    break
                }
            }
        }
    }

    /// Cancels the background listener.
    public func stop() {
        task?.cancel()
        task = nil
    }
}
