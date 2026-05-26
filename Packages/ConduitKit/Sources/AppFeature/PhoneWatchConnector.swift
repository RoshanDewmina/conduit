#if os(iOS)
import WatchConnectivity
import Foundation
import ConduitCore
import PersistenceKit
import SessionFeature

/// nonisolated WCSession bridge for the iPhone side.
/// @unchecked Sendable: NSObject is not Sendable. All let-properties are set once in init.
/// WCSession's serial delegate queue provides the necessary exclusion.
private final class WatchSessionDelegate: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let messageStream: AsyncStream<WatchSyncMessage>
    private let continuation: AsyncStream<WatchSyncMessage>.Continuation

    override init() {
        let (stream, cont) = AsyncStream<WatchSyncMessage>.makeStream()
        messageStream = stream
        continuation = cont
        super.init()
    }

    var incoming: AsyncStream<WatchSyncMessage> { messageStream }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func deliver(_ dict: [String: Any]) {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled else { return }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(dict, replyHandler: nil, errorHandler: nil)
        } else {
            try? WCSession.default.updateApplicationContext(dict)
        }
    }

    func sendApprovals(_ approvals: [Approval]) {
        let transfers = approvals.map(WatchApprovalTransfer.init)
        deliver(WatchSyncMessage.approvalSync(transfers).encode())
    }

    func sendSessionStatus(_ status: WatchSessionStatus) {
        deliver(WatchSyncMessage.sessionSync(status).encode())
    }

    func sendActivity(_ blocks: [WatchActivityBlock]) {
        deliver(WatchSyncMessage.activitySync(blocks).encode())
    }

    func sendSnippets(_ snippets: [WatchSnippet]) {
        deliver(WatchSyncMessage.snippetSync(snippets).encode())
    }

    // MARK: - Required iOS WCSessionDelegate

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let msg = WatchSyncMessage.decode(message) { continuation.yield(msg) }
    }
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if let msg = WatchSyncMessage.decode(message) { continuation.yield(msg) }
        replyHandler([:])
    }
}

/// Coordinates all Watch ↔ iPhone data sync.
/// Call `activate()` at app launch, `startSyncing(...)` each time a session starts.
@MainActor
public final class PhoneWatchConnector {
    private let delegate = WatchSessionDelegate()
    private var tasks: [Task<Void, Never>] = []

    // Callbacks set by AppRoot per-session
    public var onEmergencyStop: (@Sendable () async -> Void)?
    public var onRunSnippet: (@Sendable (String) async -> Void)?
    public var onDecision: (@Sendable (ApprovalID, Approval.Decision) async -> Void)?

    public init() {}

    public func activate() { delegate.activate() }

    public func startSyncing(
        approvalRepo: ApprovalRepository,
        blockRepo: BlockRepository,
        snippetRepo: SnippetRepository,
        sessionViewModel: SessionViewModel,
        onDecision: @escaping @Sendable (ApprovalID, Approval.Decision) async -> Void
    ) {
        stopSyncing()
        self.onDecision = onDecision

        // 1. Sync pending approvals whenever DB changes
        tasks.append(Task { [delegate] in
            do {
                for try await approvals in await approvalRepo.observe() {
                    guard !Task.isCancelled else { break }
                    delegate.sendApprovals(approvals.filter { $0.isPending })
                }
            } catch {}
        })

        // 2. Push session status every 5s
        tasks.append(Task { [delegate, weak sessionViewModel] in
            while !Task.isCancelled {
                if let vm = sessionViewModel {
                    let status = WatchSessionStatus(
                        hostName: vm.host.name,
                        hostname: vm.host.hostname,
                        isConnected: vm.status == .connected,
                        agentActive: false,  // future: track agent state
                        pendingCount: 0,     // filled by approval count separately
                        connectedAt: vm.status == .connected
                            ? Date().timeIntervalSinceReferenceDate
                            : nil
                    )
                    delegate.sendSessionStatus(status)
                }
                try? await Task.sleep(for: .seconds(5))
            }
        })

        // 3. Push recent activity every 10s
        tasks.append(Task { [delegate, weak sessionViewModel, blockRepo] in
            while !Task.isCancelled {
                if let vm = sessionViewModel {
                    let sessionID = vm.sessionID
                    if let blocks = try? await blockRepo.recent(for: sessionID, limit: 10) {
                        let watchBlocks = blocks.map { b in
                            WatchActivityBlock(
                                id: b.id.uuidString,
                                command: b.command,
                                outputPreview: String(b.joinedOutput.prefix(200)),
                                exitCode: b.exitStatus?.code,
                                isSuccess: b.exitStatus?.isSuccess,
                                startedAt: b.startedAt.timeIntervalSinceReferenceDate,
                                duration: b.duration
                            )
                        }
                        delegate.sendActivity(watchBlocks)
                    }
                }
                try? await Task.sleep(for: .seconds(10))
            }
        })

        // 4. Push snippets once at start, then every 60s
        tasks.append(Task { [delegate, snippetRepo] in
            while !Task.isCancelled {
                if let allSnippets = try? await snippetRepo.all() {
                    let watchSnippets = allSnippets.map { s in
                        WatchSnippet(id: s.id.uuidString, name: s.name, body: s.body)
                    }
                    delegate.sendSnippets(watchSnippets)
                }
                try? await Task.sleep(for: .seconds(60))
            }
        })

        // 5. Consume incoming Watch → iPhone messages
        tasks.append(Task { [delegate, weak self] in
            for await message in delegate.incoming {
                guard !Task.isCancelled, let self else { break }
                switch message {
                case .decision(let idStr, let result):
                    if let uuid = UUID(uuidString: idStr) {
                        let id = ApprovalID(uuid)
                        let decision: Approval.Decision = (result == "approved") ? .approved : .rejected
                        await self.onDecision?(id, decision)
                    }
                case .emergencyStop:
                    await self.onEmergencyStop?()
                case .runSnippet(let body):
                    await self.onRunSnippet?(body)
                default:
                    break
                }
            }
        })
    }

    public func stopSyncing() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        onEmergencyStop = nil
        onRunSnippet = nil
        onDecision = nil
    }
}
#endif
