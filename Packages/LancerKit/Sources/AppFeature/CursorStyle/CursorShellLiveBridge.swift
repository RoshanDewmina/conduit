#if os(iOS)
import Foundation
import Observation
import InboxFeature
import LancerCore
import SSHTransport
import AgentKit

/// Bridges real AppRoot infrastructure into the Cursor-style navigation shell
/// for Tier-0 phone-usable flows (workspaces, threads, dispatch, approvals).
@MainActor
@Observable
public final class CursorShellLiveBridge {
    public enum ConnectionPhase: Sendable, Equatable {
        case connected
        case reconnecting
        case offline
        case needsPairing
    }

    /// A machine that has a checkout of this repo and can run agents against it.
    public struct RunTarget: Identifiable, Sendable, Equatable {
        public let id: String          // machineID (hostID string)
        public let machineID: String
        public let hostName: String

        public init(machineID: String, hostName: String) {
            self.id = machineID
            self.machineID = machineID
            self.hostName = hostName
        }
    }

    public struct WorkspaceRow: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let threadCount: Int
        /// Distinct machines that have at least one conversation in this repo.
        public let runTargets: [RunTarget]

        public init(id: String, name: String, threadCount: Int, runTargets: [RunTarget] = []) {
            self.id = id
            self.name = name
            self.threadCount = threadCount
            self.runTargets = runTargets
        }
    }

    public struct ThreadRow: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let repoName: String
        public let updatedAt: Date?
        public let hostID: String?
        public let hostName: String?

        public init(
            id: String,
            title: String,
            repoName: String,
            updatedAt: Date?,
            hostID: String? = nil,
            hostName: String? = nil
        ) {
            self.id = id
            self.title = title
            self.repoName = repoName
            self.updatedAt = updatedAt
            self.hostID = hostID
            self.hostName = hostName
        }
    }

    public var workspaces: [WorkspaceRow] = []
    public var threadsByWorkspace: [String: [ThreadRow]] = [:]
    public var pendingApprovalID: ApprovalID?
    /// The resolved approval behind `pendingApprovalID`, set by whoever sets
    /// the ID when they already hold the object. This is Observable-TRACKED
    /// state, unlike `lookupApproval` below, whose body reads AppRoot's
    /// @State (`liveInboxVM` etc.) — state the Review sheet's render graph
    /// does not observe. When the sheet's first render raced those properties
    /// (they read nil for a few ms at launch), the lookup returned nil and
    /// nothing ever triggered a re-render: the sheet sat on "No pending
    /// approval" forever while the approval was in the store (2026-07-08,
    /// relay-approval-e2e). Setting the object here re-renders deterministically.
    public var pendingApproval: Approval?
    /// Looks up the REAL `Approval` (command, cwd, risk, agent, tool name…)
    /// behind `pendingApprovalID` — without this, CursorReviewDiffView had no
    /// way to render anything but hardcoded example content, meaning a real
    /// approval showed the WRONG command/risk/scope to the user deciding on
    /// it (2026-07-07 — found live: a fileWrite request rendered as a fake
    /// "terraform apply on production" example). A live function rather than
    /// a cached copy so it's never stale relative to `activeInboxViewModel`.
    public var lookupApproval: ((ApprovalID) -> Approval?)?
    /// `composerCWD` only ever holds a repo's display NAME (the last path
    /// component), never an absolute path — see `CursorAppShell.swift`'s repo
    /// navigation/thread-select call sites. `repoPaths` maps that display name
    /// back to the real, daemon-resolved absolute cwd of its most recent known
    /// conversation, so a fresh dispatch (no existing thread/cwd to reuse) can
    /// still launch in the right directory instead of sending the bare name
    /// itself as `cwd` (which the daemon's `expandHome` can't resolve — it only
    /// expands `~`, so a bare repo name fails `cmd.Start()` with a bogus
    /// relative-to-launchd's-own-cwd path).
    public var repoPaths: [String: String] = [:]
    public var composerCWD: String = ""
    public var selectedThreadID: String?
    /// Real state for the work-thread screen currently on top of the nav
    /// stack — replaces what used to be 100% hardcoded mock content
    /// (CursorWorkThreadView.swift) with the actual dispatched prompt and its
    /// live/streamed response. `activeRunID` is set the instant a dispatch
    /// starts so the app-level run-output notification handlers (AppRoot's
    /// `lancerE2ERunOutput`/`lancerE2ERunStatus`) know which run to mirror
    /// onto `activeThreadResponse`.
    public var activeThreadPrompt: String = ""
    public var activeThreadResponse: String = ""
    public var activeRunID: String?
    public var activeThreadIsWorking: Bool = false
    public var activeThreadError: String?
    /// Artifacts for the active thread/run — receipt cards render from here.
    public var activeThreadArtifacts: [ChatArtifact] = []
    /// Prefill text for the next composer open (e.g. "Request another pass").
    public var composerPrefillText: String?
    /// Working directory used when building resume commands for receipts.
    public var activeThreadCWD: String?
    /// OpenRouter / vendor model slug used for the next dispatch from the composer.
    public var composerModelSlug: String = ManagedModel.claudeHaiku.rawValue
    public var composerModelLabel: String = ManagedModel.claudeHaiku.label
    public var connectionPhase: ConnectionPhase = .connected
    public var threadAttention: [String: CursorThreadAttention] = [:]
    /// Published inputs for `CursorThreadAttention.derive` per conversation id.
    public var threadStates: [String: CursorThreadAttention.ThreadState] = [:]
    /// When `refreshCursorLiveBridge` last completed — drives stale-relay copy.
    public var lastSnapshotAt: Date?

    public var relayHealthy: Bool { connectionPhase == .connected }

    /// Called when the user submits an answer to a question card. The artifact is
    /// provided so the caller can update its payloadJSON with the answered state via
    /// `QuestionCardModel.mergeAnswer` and re-persist via `upsertArtifact`.
    /// The `QuestionAnswerParams` should be forwarded to the daemon via
    /// `DaemonChannel.sendQuestionAnswer` or `E2ERelayBridge.sendQuestionAnswer`.
    public var onAnswerQuestion: ((ChatArtifact, QuestionAnswerParams) async -> Void)?

    public var observedSessions: [CursorObservedSessionMapping.RowModel] = []
    /// Bumps the same refresh trigger the workspace/thread list uses (AppRoot's
    /// `workspacesRevision` → `refreshCursorLiveBridge`).
    public var onRequestRefresh: (() -> Void)?
    /// Imports a terminal-originated session via `agent.conversations.attachObservedSession`
    /// and returns the resulting Lancer `conversationId`, or an error message.
    public var onImportObservedSession: ((CursorObservedSessionMapping.RowModel) async -> Result<String, CursorObservedSessionImportError>)?

    public var onDispatch: ((String, String, String?, ProofReceipt.Contract?) async -> Void)?
    public var onContinue: ((String, String, String?, ProofReceipt.Contract?) async -> Void)?
    /// Loads a selected EXISTING thread's real, already-persisted content
    /// (prompt + assistant text of its most recent turn) into
    /// `activeThread*` — without this, opening an old thread always showed
    /// the generic "No output recorded" placeholder even for a thread with a
    /// real, complete saved response (2026-07-07).
    public var onOpenThread: ((String) async -> Void)?
    /// Real full-text search over conversation history (title/prompt/
    /// assistant-text/artifact-text, via the existing `chat_fts` table) — the
    /// search overlay previously filtered a 5-row hardcoded list client-side
    /// and never searched anything real (2026-07-07).
    public var onSearch: ((String) async -> [ChatConversationSearchResult])?
    public var onDecide: ((ApprovalID, Approval.Decision) async -> Void)?
    public var onAcceptReceipt: ((ChatArtifact) async -> Void)?
    public var onRequestPairing: (() -> Void)?
    /// Opens the app-level Review sheet (`AppRoot.showingApprovalReview`) so a
    /// dismissed approval can be recovered from Workspaces / thread list — not
    /// only from the Work Thread banner (2026-07-08 frontend audit).
    public var onOpenReview: (() -> Void)?
    public var onPaired: ((E2ERelayClient, RelayMachineRecord) -> Void)?
    public var onClearInvalid: (() -> Void)?
    public var relayMachineCount: Int = 0
    public var invalidMachineCount: Int = 0

    public init() {}

    public func threads(for workspaceName: String) -> [ThreadRow] {
        threadsByWorkspace[workspaceName] ?? []
    }

    public func reloadWorkspaces(
        from names: [String],
        threadCounts: [String: Int],
        runTargetsByRepo: [String: [RunTarget]] = [:]
    ) {
        workspaces = names.map { name in
            WorkspaceRow(
                id: name,
                name: name,
                threadCount: threadCounts[name] ?? 0,
                runTargets: runTargetsByRepo[name] ?? []
            )
        }
    }

    public func reloadThreads(workspaceName: String, rows: [ThreadRow]) {
        threadsByWorkspace[workspaceName] = rows
    }
}
#endif
