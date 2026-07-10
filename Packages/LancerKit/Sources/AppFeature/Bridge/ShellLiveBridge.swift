#if os(iOS)
import Foundation
import Observation
import LancerCore
import PersistenceKit
import SessionFeature

/// M3: the one piece of "engine" glue code connecting the New Chat composer's
/// send action to the real host-mediated conversation pipeline —
/// `RelayFleetStore` (M2's paired machines) → `E2ERelayBridge` (the wire
/// transport) → `ConversationSyncCoordinator` (append/fetch orchestration +
/// local GRDB mirror). Everything else in `Chat/` is display only; this type
/// owns the send → poll-until-terminal → publish state machine.
///
/// Hardcodes vendor `"claudeCode"` (no vendor picker UI exists yet — see the
/// M3 brief) and polls `ChatConversationRepository.turnByRunID` rather than
/// consuming a token-level stream: the Plan's M3 acceptance explicitly
/// allows "streamed (or completed) reply visible," and true token streaming
/// is out of scope for this milestone.
@MainActor
@Observable
public final class ShellLiveBridge {
    public enum SendState: Equatable {
        case idle
        case working
        case completed(LancerCore.ChatTurn)
        case failed(String)

        public static func == (lhs: SendState, rhs: SendState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.working, .working):
                return true
            case (.completed(let l), .completed(let r)):
                return l.id == r.id && l.status == r.status && l.assistantText == r.assistantText
            case (.failed(let l), .failed(let r)):
                return l == r
            default:
                return false
            }
        }
    }

    public private(set) var sendState: SendState = .idle
    public private(set) var activeConversationID: String?
    /// M4: the machine the most recent send/follow-up resolved via
    /// `RelayFleetStore.firstConnectedMachine`. `LiveThreadView` reads this to
    /// look up `RelayApprovalIngest.latestPendingApproval[activeMachineID]` —
    /// see that type's doc comment for why this is machine-scoped, not
    /// run-scoped.
    public private(set) var activeMachineID: RelayMachineID?

    private let relayFleetStore: RelayFleetStore
    private let conversationSyncCoordinator: ConversationSyncCoordinator
    private let chatRepo: ChatConversationRepository

    /// This milestone hardcodes the vendor CLI — no picker UI exists yet.
    private static let vendor = "claudeCode"
    private static let pollInterval: UInt64 = 1_500_000_000
    private static let pollTimeout: TimeInterval = 90

    public init(
        relayFleetStore: RelayFleetStore,
        conversationSyncCoordinator: ConversationSyncCoordinator,
        chatRepo: ChatConversationRepository
    ) {
        self.relayFleetStore = relayFleetStore
        self.conversationSyncCoordinator = conversationSyncCoordinator
        self.chatRepo = chatRepo
    }

    /// Starts a brand-new conversation on the first connected paired machine
    /// and polls for the reply. No-op if a send is already in flight.
    public func send(prompt: String, cwd: String) async {
        guard sendState != .working else { return }
        guard let machine = relayFleetStore.firstConnectedMachine else {
            sendState = .failed("No connected machine. Pair one in Settings → Trusted Machines.")
            return
        }
        activeMachineID = machine.id

        sendState = .working
        activeConversationID = nil

        let transport = Self.transport(for: machine.bridge)
        let outcome = await conversationSyncCoordinator.startConversation(
            agent: "relay|\(machine.id.uuidString)|\(Self.vendor)",
            cwd: cwd,
            prompt: prompt,
            model: nil,
            budgetUSD: nil,
            hostName: machine.record.displayName,
            hostID: machine.id.uuidString,
            clientTurnID: UUID().uuidString,
            transport: transport
        )

        switch outcome {
        case .started(let started):
            activeConversationID = started.conversationID
            await pollUntilTerminal(runID: started.runID, conversationID: started.conversationID, transport: transport)
        case .blocked(let message):
            sendState = .failed(message)
        }
    }

    /// Appends a follow-up turn to the active conversation and polls for the
    /// reply. Reads the conversation's current `lastHostSeq` as `baseSeq`.
    /// No-op if there's no active conversation or a send is already in flight.
    public func sendFollowUp(prompt: String, conversationID: String, cwd: String) async {
        guard sendState != .working else { return }
        guard let machine = relayFleetStore.firstConnectedMachine else {
            sendState = .failed("No connected machine. Pair one in Settings → Trusted Machines.")
            return
        }
        activeMachineID = machine.id

        let baseSeq = (try? await chatRepo.conversation(id: conversationID))?.lastHostSeq ?? 0

        sendState = .working

        let transport = Self.transport(for: machine.bridge)
        let outcome = await conversationSyncCoordinator.continueConversation(
            conversationID: conversationID,
            baseSeq: baseSeq,
            prompt: prompt,
            clientTurnID: UUID().uuidString,
            hostName: machine.record.displayName,
            hostID: machine.id.uuidString,
            transport: transport
        )

        switch outcome {
        case .started(let started):
            activeConversationID = started.conversationID
            await pollUntilTerminal(runID: started.runID, conversationID: started.conversationID, transport: transport)
        case .blocked(let message):
            sendState = .failed(message)
        }
    }

    /// Polls the local GRDB mirror until the turn leaves `.running`, up to
    /// `pollTimeout`. A plain local re-read alone is NOT enough: nothing
    /// updates the mirror's turn status after the initial append
    /// (`persistStartedTurn` in `ConversationSyncCoordinator` writes it once,
    /// at append time) until a host fetch happens
    /// (`refreshConversation`/`mergeFetchResponse`). Without periodically
    /// re-fetching from the host here, this loop would silently time out
    /// after `pollTimeout` on every real host, always — the local row simply
    /// never changes on its own. Fetches every 2nd tick (~3s) rather than
    /// every tick (1.5s) to avoid excessive network chatter.
    private func pollUntilTerminal(runID: String, conversationID: String, transport: ConversationTransport) async {
        let deadline = Date().addingTimeInterval(Self.pollTimeout)
        var tick = 0
        while Date() < deadline {
            tick += 1
            if tick % 2 == 0 {
                _ = try? await conversationSyncCoordinator.refreshConversation(
                    conversationID: conversationID, transport: transport
                )
            }
            if let turn = try? await chatRepo.turnByRunID(runID), turn.status != .running {
                switch turn.status {
                case .completed:
                    sendState = .completed(turn)
                case .failed:
                    sendState = .failed(turn.errorMessage ?? "Run failed")
                case .running:
                    break
                }
                return
            }
            try? await Task.sleep(nanoseconds: Self.pollInterval)
        }
        sendState = .failed("Timed out waiting for a reply.")
    }

    private static func transport(for bridge: E2ERelayBridge) -> ConversationTransport {
        ConversationTransport(
            append: { try await bridge.relayAppendConversation($0) },
            fetch: { try await bridge.relayFetchConversation($0) },
            archive: { try await bridge.relayArchiveConversation($0) }
        )
    }
}
#endif
