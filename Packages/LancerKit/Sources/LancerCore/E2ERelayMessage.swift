import Foundation

/// Message types sent through the E2E encrypted relay
public enum E2ERelayMessage: Codable, Sendable {
    /// Agent needs approval - sent daemon → phone
    case approvalPending(ApprovalData)
    /// User decision - sent phone → daemon
    case approvalResponse(DecisionData)
    /// Agent status update - sent daemon → phone
    case agentStatus(StatusData)
    /// Loop progress update - sent daemon → phone
    case loopUpdate(LoopData)
    /// Explicit ack that the daemon processed (or failed to process) a decision
    /// - sent daemon → phone, in reply to approvalResponse. A successful outgoing
    /// send is not proof of delivery; this closes that gap.
    case approvalResponseAck(DecisionAckData)
    /// The daemon resolved a pending approval without ever receiving a decision
    /// from this client (e.g. the 120s fail-closed timeout fired) - sent
    /// daemon → phone, so a stale pending card can be cleared proactively.
    case approvalResolved(ResolvedData)
    /// Ack for `deviceRegister` carrying the daemon's per-session capability
    /// token - sent daemon → phone. The SSH channel's `registerDevice()` RPC
    /// returns this token in its reply; the relay's `deviceRegister` message
    /// used to be pure fire-and-forget, so a relay-only pairing (no SSH host)
    /// never learned it and `ApprovalRelay.postDecisionToBackend` — the only
    /// fallback when the direct `approvalResponse` send fails to get acked —
    /// was permanently a silent no-op.
    case deviceRegistered(DeviceRegisteredData)
    /// Forwards a Live Activity (ActivityKit) push or push-to-start token to the
    /// relay-paired daemon so it can register it with push-backend on the
    /// phone's behalf - sent phone → daemon. Mirrors `deviceRegister`
    /// (APNs device tokens): the relay-only path had no equivalent for Live
    /// Activity tokens, so `AppRoot`'s `.lancerLiveActivityTokenReady`
    /// subscriber only ever forwarded them over `DaemonChannel` (SSH), which
    /// doesn't exist for a relay-only pairing — closed-app push-driven Live
    /// Activity updates never worked on relay-only devices.
    case activityTokenRegister(ActivityTokenRegisterData)
    /// Ping/pong keepalive
    case ping
    case pong

    public struct ApprovalData: Codable, Sendable {
        public let approvalID: String
        public let agent: String
        public let kind: String
        public let command: String?
        public let patch: String?
        public let risk: Int
        public let cwd: String?
        public let toolName: String?
        public let toolInput: String?
        /// The daemon's `computeContentHash` over (command, patch, cwd, toolInput)
        /// at approval-creation time — see `Approval.computeContentHash`.
        public let contentHash: String?

        public init(approvalID: String, agent: String, kind: String, command: String?, patch: String? = nil, risk: Int, cwd: String?, toolName: String?, toolInput: String? = nil, contentHash: String? = nil) {
            self.approvalID = approvalID
            self.agent = agent
            self.kind = kind
            self.command = command
            self.patch = patch
            self.risk = risk
            self.cwd = cwd
            self.toolName = toolName
            self.toolInput = toolInput
            self.contentHash = contentHash
        }
    }

    public struct DecisionData: Codable, Sendable {
        public let approvalID: String
        public let decision: String
        public let editedToolInput: String?
        /// Echoed back from the `ApprovalData.contentHash` this decision was
        /// made on; lancerd's approvalStore.resolve rejects a mismatch.
        public let contentHash: String?

        public init(approvalID: String, decision: String, editedToolInput: String?, contentHash: String? = nil) {
            self.approvalID = approvalID
            self.decision = decision
            self.editedToolInput = editedToolInput
            self.contentHash = contentHash
        }
    }

    public struct DecisionAckData: Codable, Sendable {
        public let approvalID: String
        public let ok: Bool

        public init(approvalID: String, ok: Bool) {
            self.approvalID = approvalID
            self.ok = ok
        }
    }

    public struct ResolvedData: Codable, Sendable {
        public let approvalID: String
        public let decision: String

        public init(approvalID: String, decision: String) {
            self.approvalID = approvalID
            self.decision = decision
        }
    }

    public struct DeviceRegisteredData: Codable, Sendable {
        public let relayToken: String

        public init(relayToken: String) {
            self.relayToken = relayToken
        }
    }

    /// Params for `activityTokenRegister` - mirrors `DaemonChannel.registerActivityToken`'s
    /// `lancer.device.register.activity` RPC params, sent over the relay instead of SSH.
    public struct ActivityTokenRegisterData: Codable, Sendable {
        public let sessionId: String
        public let activityToken: String
        public let isPushToStart: Bool
        public let pushBackendURL: String

        public init(sessionId: String, activityToken: String, isPushToStart: Bool, pushBackendURL: String) {
            self.sessionId = sessionId
            self.activityToken = activityToken
            self.isPushToStart = isPushToStart
            self.pushBackendURL = pushBackendURL
        }
    }

    public struct StatusData: Codable, Sendable {
        public let agent: String
        public let model: String?
        public let sessionCount: Int
        public let usageUSD: Double?
        public let hostName: String?

        public init(agent: String, model: String?, sessionCount: Int, usageUSD: Double?, hostName: String? = nil) {
            self.agent = agent
            self.model = model
            self.sessionCount = sessionCount
            self.usageUSD = usageUSD
            self.hostName = hostName
        }
    }

    public struct LoopData: Codable, Sendable {
        public let loopID: String
        public let status: String
        public let currentStep: String?
        public let spendUSD: Double?

        public init(loopID: String, status: String, currentStep: String?, spendUSD: Double?) {
            self.loopID = loopID
            self.status = status
            self.currentStep = currentStep
            self.spendUSD = spendUSD
        }
    }

    /// Dispatch params sent phone → daemon over the relay.
    public struct DispatchParams: Codable, Sendable {
        public let agent: String
        public let cwd: String
        public let prompt: String
        public let model: String?
        public let budgetUSD: Double

        public init(agent: String, cwd: String, prompt: String, model: String? = nil, budgetUSD: Double = 0) {
            self.agent = agent
            self.cwd = cwd
            self.prompt = prompt
            self.model = model
            self.budgetUSD = budgetUSD
        }
    }

    /// Wrapper for an inner relay message with a typed payload field.
    public struct RelayInnerEnvelope<T: Codable & Sendable>: Codable, Sendable {
        public let type: String
        public let payload: T
        public init(type: String, payload: T) {
            self.type = type
            self.payload = payload
        }
    }
}

/// A file's content returned by the daemon's `fsRead` over the relay. Keys
/// mirror the Go `fsReadResult` JSON (`path`, `content`, `truncated`), plus an
/// optional `error` the router sets when the home-confined `fsRead` fails
/// (path escape, directory, or binary content).
public struct RelayFileContent: Codable, Sendable {
    public let path: String
    public let content: String
    public let truncated: Bool
    public let error: String?

    public init(path: String, content: String, truncated: Bool = false, error: String? = nil) {
        self.path = path
        self.content = content
        self.truncated = truncated
        self.error = error
    }
}
