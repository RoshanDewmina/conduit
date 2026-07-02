#if os(iOS)
import SwiftUI
import UIKit
import DesignSystem
import SessionFeature
import AgentKit
import PersistenceKit
import SSHTransport
import LancerCore
import InboxFeature

// MARK: - DispatchAgent

public struct DispatchAgent: Identifiable {
    public let id: String
    public let name: String
    public let cwd: String
    public let isOffline: Bool
    public let hostID: String?
    public let hostName: String?

    /// The agent kind after the "|" separator in id, e.g. "opencode", "claudeCode", "codex".
    public var vendor: String {
        id.split(separator: "|", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
    }

    public init(id: String, name: String, cwd: String, isOffline: Bool, hostID: String? = nil, hostName: String? = nil) {
        self.id = id
        self.name = name
        self.cwd = cwd
        self.isOffline = isOffline
        self.hostID = hostID
        self.hostName = hostName
    }
}

/// One turn in an inline conversation: a user prompt and the runId of the agent
/// process launched to answer it. A follow-up appends a new turn under a new runId.
struct ChatTurn: Identifiable {
    let prompt: String
    let runId: String
    var id: String { runId }
}

public struct NewChatTabView: View {
    let agents: [DispatchAgent]
    let runOutputStore: RunOutputStore
    let chatRepo: ChatConversationRepository?
    let fleetStore: FleetStore
    let onDispatch: (_ agentID: String, _ cwd: String, _ prompt: String, _ budgetUSD: Double?, _ model: String?) async -> ChatDispatchOutcome
    let onNewTask: () -> Void
    let onOpenWorkspace: (DispatchAgent?) -> Void
    var onOpenSidebar: () -> Void = {}
    /// Invoked when the user taps "Connect this machine over SSH" from the
    /// SSH-features upsell sheet. Defaults to a no-op so existing call sites compile.
    var onConnectSSH: () -> Void = {}
    /// Fetches the agent's live slash-commands for a workspace (daemon-backed).
    /// Defaults to none so previews/tests don't need a live channel.
    var loadCommands: (_ cwd: String, _ vendor: String) async -> [AgentCommand] = { _, _ in [] }
    /// Fetches workspace file/dir names for @-mention autocomplete. Defaults to none.
    var loadFiles: (_ cwd: String) async -> [String] = { _ in [] }
    /// The inbox VM whose pending approvals block active runs. nil → no inline card.
    var inboxViewModel: InboxViewModel? = nil
    /// Routes an approve/deny decision through the same path as the Inbox.
    var onDecideApproval: (ApprovalID, Approval.Decision) -> Void = { _, _ in }

    @State private var prompt: String = ""
    @State private var selectedAgentID: String = ""
    /// Empty ⇒ use the selected agent's default cwd. A non-empty value is an explicit
    /// project directory the user picked for this run (the Omnara "in [workspace]" slot).
    @State private var selectedCwd: String = ""
    @State private var customCwd: String = ""
    @State private var showContextPicker = false
    @State private var showComposer = false
    @State private var showOptions = false
    @State private var selectedModel: String = ""
    @State private var budgetText: String = ""

    // Inline conversation state — set once a dispatch starts; nil shows the
    // compose screen.
    @State private var activeRun: ActiveChatRun?
    /// Stable Live Activity key for this whole chat thread — set once, from the
    /// FIRST dispatched run's id, and reused across follow-up turns (each of
    /// which mints its own new `runId`). One thread = one continuous Live
    /// Activity, mirroring how `SessionViewModel` keys its activity by the
    /// whole session's id, not by each individual command run within it.
    @State private var liveActivityKey: String?
    @State private var controlStore: RunControlStore?
    @State private var chatTitle: String = "new chat"
    // One conversation = an ordered list of (prompt, runId) turns. The first is the
    // initial dispatch; each follow-up appends a new turn under a new runId.
    @State private var turns: [ChatTurn] = []
    @State private var followUpText: String = ""
    @State private var confirmStop = false
    @State private var showBudgetSheet = false
    @State private var showSSHFeatures = false
    @State private var dispatchErrorMessage: String?
    /// Set when a follow-up returns "needsApproval" — drives the inline approval card
    /// in assistantTurn. Cleared on decision, reset, or new run.
    @State private var isAwaitingApproval = false
    /// True while a dispatch/continue is awaiting the daemon's reply — disables Send
    /// so a second tap can't fire a duplicate run (the "superseded" cause).
    @State private var isSending = false
    /// Recently-used custom project paths, newest first, persisted so a path the
    /// user typed once is reusable from the picker instead of retyped each time.
    @AppStorage("lancer.recentProjectPaths") private var recentProjectPathsRaw: String = ""
    /// Last-used machine / workspace / model, persisted so the next New Chat entry
    /// resumes the prior context instead of always defaulting to "first online agent".
    @AppStorage("lancer.newChat.lastMachine") private var lastMachineID: String = ""
    @AppStorage("lancer.newChat.lastWorkspace") private var lastWorkspacePath: String = ""
    @AppStorage("lancer.newChat.lastModel") private var lastModelID: String = ""

    // Persistence
    @State private var conversationID: String?
    @State private var artifactsByRun: [String: [ChatArtifact]] = [:]
    @State private var selectedArtifact: ChatArtifact?
    @FocusState private var composeFocused: Bool

    @Environment(\.lancerTokens) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        agents: [DispatchAgent],
        runOutputStore: RunOutputStore,
        chatRepo: ChatConversationRepository? = nil,
        fleetStore: FleetStore,
        onDispatch: @escaping (_ agentID: String, _ cwd: String, _ prompt: String, _ budgetUSD: Double?, _ model: String?) async -> ChatDispatchOutcome,
        onNewTask: @escaping () -> Void,
        onOpenWorkspace: @escaping (DispatchAgent?) -> Void = { _ in },
        onOpenSidebar: @escaping () -> Void = {},
        onConnectSSH: @escaping () -> Void = {},
        loadCommands: @escaping (_ cwd: String, _ vendor: String) async -> [AgentCommand] = { _, _ in [] },
        loadFiles: @escaping (_ cwd: String) async -> [String] = { _ in [] },
        inboxViewModel: InboxViewModel? = nil,
        onDecideApproval: @escaping (ApprovalID, Approval.Decision) -> Void = { _, _ in }
    ) {
        self.agents = agents
        self.runOutputStore = runOutputStore
        self.chatRepo = chatRepo
        self.fleetStore = fleetStore
        self.onDispatch = onDispatch
        self.onNewTask = onNewTask
        self.onOpenWorkspace = onOpenWorkspace
        self.onOpenSidebar = onOpenSidebar
        self.onConnectSSH = onConnectSSH
        self.loadCommands = loadCommands
        self.loadFiles = loadFiles
        self.inboxViewModel = inboxViewModel
        self.onDecideApproval = onDecideApproval
    }

    // MARK: - Slash commands

    /// Lancer's own composer commands — client-side actions, distinct from the
    /// agent's live commands. `kind: "lancer"` so the autocomplete badges them "app".
    private static let lancerCommands: [AgentCommand] = [
        AgentCommand(name: "/new", description: "Start a fresh chat", source: "lancer", kind: "lancer"),
        AgentCommand(name: "/clear", description: "Clear this draft", source: "lancer", kind: "lancer"),
        AgentCommand(name: "/model", description: "Choose the model", source: "lancer", kind: "lancer"),
        AgentCommand(name: "/budget", description: "Set a budget cap", source: "lancer", kind: "lancer"),
        AgentCommand(name: "/agent", description: "Switch agent or host", source: "lancer", kind: "lancer"),
        AgentCommand(name: "/workspace", description: "Pick the project directory", source: "lancer", kind: "lancer"),
    ]

    @State private var agentCommands: [AgentCommand] = []
    @State private var workspaceFiles: [String] = []

    private func refreshCommands() async {
        guard let agent = selectedAgent, !agent.isOffline else { agentCommands = []; return }
        let cmds = await loadCommands(effectiveCwd, agent.vendor)
        await MainActor.run { agentCommands = cmds }
    }

    /// Fetch workspace files lazily, only once the user starts an @-mention, so we
    /// don't list the host on every composer open.
    private func refreshFilesIfMentioning() async {
        guard FileMentionBar.activeToken(in: prompt) != nil, workspaceFiles.isEmpty else { return }
        let files = await loadFiles(effectiveCwd)
        await MainActor.run { workspaceFiles = files }
    }

    /// Replace the trailing "@token" with the picked file path + a trailing space.
    private func insertFileMention(_ file: String) {
        guard let at = prompt.lastIndex(of: "@") else { return }
        prompt = String(prompt[..<at]) + "@" + file + " "
    }

    /// A composer `/` pick: Lancer commands run their action; agent commands insert
    /// their token into the prompt so the user keeps typing the rest of the request.
    private func handleComposerPick(_ cmd: AgentCommand) {
        if cmd.kind == "lancer" {
            prompt = ""
            switch cmd.name {
            case "/new", "/clear": prompt = ""
            case "/budget": showComposer = true
            case "/model", "/agent": showContextPicker = true
            case "/workspace": customCwd = ""; showContextPicker = true
            default: break
            }
        } else {
            prompt = cmd.name + " "
        }
    }

    // MARK: - Derived run state (mirrors RunDetailView's, scoped to this thread's run)

    private var currentRun: RunOutputStore.Run? {
        guard let activeRun else { return nil }
        return runOutputStore.run(activeRun.runId)
    }

    private var agentState: AgentState {
        guard let run = currentRun else { return .thinking }
        switch run.status {
        case "running": return run.chunks.isEmpty ? .thinking : .streaming
        case "exited":  return .done
        case "failed":  return .error
        default:        return run.chunks.isEmpty ? .thinking : .streaming
        }
    }

    private var isStreaming: Bool {
        controlStore?.status == .running && agentState != .done && agentState != .error
    }

    private var runIsTerminal: Bool { currentRun?.isTerminal ?? false }

    private var isErrorState: Bool {
        currentRun?.status == "failed" || (controlStore?.lastError != nil && controlStore?.status != .running)
    }

    /// The first pending approval from the inbox — used to render the inline card
    /// when a run is paused waiting for a decision. Approval carries no runId so we
    /// surface the most-recent pending one whenever isAwaitingApproval is set.
    private var pendingApproval: Approval? {
        inboxViewModel?.approvals.first(where: \.isPending)
    }

    /// The most-recently-decided blocked approval (rejected or expired). Read only
    /// while `isAwaitingApproval` is set, so it reflects the run the user just
    /// denied — used to render a clear "Denied" state instead of a typing dot.
    private var deniedApproval: Approval? {
        inboxViewModel?.approvals
            .filter { $0.decision == .rejected || $0.decision == .expired }
            .max { ($0.decidedAt ?? .distantPast) < ($1.decidedAt ?? .distantPast) }
    }

    /// Count of pending approvals visible to this VM — read purely as an
    /// `.onChange` trigger. `isAwaitingApproval` used to flip on ONLY from the
    /// synchronous dispatch/continueRun "needsApproval" reply, so a mid-run
    /// PreToolUse-hook escalation (delivered async: daemon → relay →
    /// `lancerE2EApprovalReceived` → `inboxViewModel.approvals`, no synchronous
    /// reply involved at all) never turned the inline card on — the run just sat
    /// there with a typing dot while the daemon's 120s fail-closed timeout ran out
    /// with no way for the human to see or answer the gate. Approvals carry no
    /// runId (see AppRoot's relay-approval ingestion), so this is the same
    /// best-effort "most recent pending" scoping `pendingApproval` already used.
    private var pendingApprovalCount: Int {
        inboxViewModel?.approvals.filter(\.isPending).count ?? 0
    }

    public var body: some View {
        VStack(spacing: 0) {
            if activeRun != nil {
                darkChatHeader
                ConversationScrollView(bottomID: "newchat-bottom", scrollKey: currentRun?.chunks.count ?? 0) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(turns) { turn in
                            turnView(turn)
                        }
                    }
                }
                bottomBar
            } else {
                composerLanding
            }
        }
        // Chat follows the app's light/dark scheme (inherits the parent's tokens);
        // terminal blocks keep their own terminal palette via term* tokens.
        .background(t.bg.ignoresSafeArea())
        .onAppear { restoreLastSelectionOrDefault() }
        .task(id: selectedAgentID) { await refreshCommands() }
        .onChange(of: showComposer) { _, open in
            if open { Task { await refreshCommands() } }
        }
        .onChange(of: prompt) { _, _ in
            Task { await refreshFilesIfMentioning() }
        }
        // Catches a mid-run escalation the instant it lands in `inboxViewModel`,
        // instead of only reacting to a synchronous dispatch/continueRun reply
        // (see `pendingApprovalCount`'s doc comment). `initial: true` also covers
        // reopening this thread while an approval that arrived in the background
        // is still pending.
        .onChange(of: pendingApprovalCount, initial: true) { _, count in
            guard activeRun != nil, !runIsTerminal, count > 0 else { return }
            isAwaitingApproval = true
        }
        // Ends this thread's Live Activity when the run finishes — AppRoot's
        // updatePendingApprovals broadcast already keeps the approval count
        // fresh on every active activity app-wide, so only start/end/status
        // are this view's own responsibility.
        .onChange(of: runIsTerminal) { _, terminal in
            guard terminal, let key = liveActivityKey else { return }
            Task { await LancerLiveActivityManager.shared.end(activityKey: key) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lancerChatArtifactPersisted)) { note in
            guard let cid = note.userInfo?["conversationID"] as? String, cid == conversationID else { return }
            Task { await loadArtifacts() }
        }
        .bottomDrawer(
            isPresented: $showContextPicker,
            title: "Chat context",
            subtitle: "Choose the machine, workspace, and model for this run.",
            detents: [.medium, .large]
        ) {
            contextPickerContent
        }
        .bottomDrawer(
            isPresented: $showBudgetSheet,
            title: "Budget cap",
            subtitle: "Set a daily limit for this run.",
            detents: [.height(300)]
        ) {
            BudgetSheet { usd in Task { await controlStore?.setBudget(usd) } }
        }
        .bottomDrawer(
            isPresented: $showSSHFeatures,
            detents: [.large]
        ) {
            RelayWorkspaceUnavailableView(onConnectSSH: { showSSHFeatures = false; onConnectSSH() })
        }
        .bottomDrawer(
            isPresented: $showComposer,
            title: "Budget cap",
            subtitle: "Set a spending cap for this run before you send.",
            detents: [.medium, .large]
        ) {
            budgetOptionsContent
        }
        .sheet(item: $selectedArtifact) { artifact in
            ChatArtifactDetailView(artifact: artifact)
        }
        .confirmationDialog("Stop this run?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop run", role: .destructive) {
                Haptics.warning()
                Task { await controlStore?.stop() }
            }
            Button("Keep running", role: .cancel) {}
        } message: {
            Text("The agent process is terminated. This can't be undone.")
        }
        .alert("Couldn't send", isPresented: Binding(
            get: { dispatchErrorMessage != nil },
            set: { if !$0 { dispatchErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { dispatchErrorMessage = nil }
        } message: {
            Text(dispatchErrorMessage ?? "")
        }
    }

    // MARK: - Composer landing (calm idle surface) + drawer

    /// The idle New Chat surface: a calm greeting with an always-visible composer
    /// pinned to the bottom (ChatGPT/Claude style) — type immediately, no drawer
    /// tap. The "…" affordance still opens the drawer for advanced options
    /// (project picker, budget).
    private var composerLanding: some View {
        VStack(spacing: 0) {
            HStack {
                DSCircleButton(
                    "line.3.horizontal",
                    diameter: 40,
                    accessibilityLabel: "Open navigation",
                    action: onOpenSidebar
                )
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            Spacer()
            VStack(spacing: 10) {
                DSIconView(.sparkles, size: 30, color: t.accent)
                Text("New chat")
                    .font(.dsDisplayPt(28, weight: .bold))
                    .foregroundStyle(t.text)
                Text("Describe the work. Lancer routes it through policy before anything runs.")
                    .font(.dsSansPt(14))
                    .foregroundStyle(t.text3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
            }
            Spacer()
            inlineComposer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Always-visible bottom composer: "/" autocomplete, a growing prompt field
    /// with inline send, and a row of agent/host chips + an Options affordance.
    private var inlineComposer: some View {
        VStack(spacing: 8) {
            CommandAutocompleteBar(
                query: prompt,
                lancerCommands: Self.lancerCommands,
                agentCommands: agentCommands,
                onPick: handleComposerPick
            )
            .padding(.horizontal, 14)

            FileMentionBar(query: prompt, files: workspaceFiles, onPick: insertFileMention)
                .padding(.horizontal, 14)

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message — / for commands, @ for files…", text: $prompt, axis: .vertical)
                    .font(.dsSansPt(16))
                    .foregroundStyle(t.text)
                    .tint(t.accent)
                    .lineLimit(1...6)
                    .focused($composeFocused)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { composeFocused = false }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(t.border.opacity(0.72), lineWidth: 1)
                    )
                Button {
                    composeFocused = false
                    Task { await sendCurrentPrompt() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(canSend || isSending ? t.accent : t.surface2)
                            .frame(width: 44, height: 44)
                        if isSending {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(t.accentFg)
                        } else {
                            DSIconView(.send, size: 17, color: canSend ? t.accentFg : t.text4)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send chat")
            }
            .padding(.horizontal, 14)

            HStack(spacing: 8) {
                Button { showContextPicker = true } label: {
                    HStack(spacing: 5) {
                        DSStatusDot(tone: selectedAgent?.isOffline == true ? .off : .accent, size: 7)
                        ViewThatFits(in: .horizontal) {
                            Text(contextPillFullText)
                                .lineLimit(1)
                            Text(contextPillCompactText)
                                .lineLimit(1)
                        }
                        .font(.dsSansPt(12.5, weight: .semibold))
                        .foregroundStyle(t.text2)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(t.surface, in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Button { showComposer = true } label: {
                    Image(systemName: "dollarsign.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(t.text3)
                        .frame(width: 32, height: 32)
                        .background(t.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Budget options")
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 10)
        .background(t.bg.ignoresSafeArea(edges: .bottom))
    }

    /// Config-only sheet opened by the composer's budget control. Machine, workspace,
    /// and model now live in `contextPickerContent` (one tap on the composer pill) —
    /// this sheet is deliberately minimal, budget-only, since that's all that's left
    /// once Model moved out. The prompt and Send live on the composer landing; this
    /// sheet never duplicates them, it just sets the cap for the next dispatch.
    private var budgetOptionsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                budgetField

                Button {
                    Haptics.selection()
                    showComposer = false
                } label: {
                    Text("Done")
                        .font(.dsSansPt(16, weight: .semibold))
                        .foregroundStyle(t.accentFg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(t.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Done setting the budget")
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Conversation turns

    @ViewBuilder
    private func turnView(_ turn: ChatTurn) -> some View {
        userTurn(turn.prompt)
        assistantTurn(for: turn)
    }

    private func userTurn(_ promptText: String) -> some View {
        DarkUserBubble(promptText)
            .contextMenu {
                Button {
                    UIPasteboard.general.string = promptText
                    Haptics.success()
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                Button {
                    // Edit & resend: load this prompt into the follow-up field for
                    // editing; sending it continues the run as a fresh turn.
                    Haptics.selection()
                    followUpText = promptText
                } label: { Label("Edit & resend", systemImage: "pencil") }
            }
    }

    // Transcript chrome follows the app theme; only the terminal output card is
    // intentionally dark so an active conversation doesn't create a second app skin.
    private var darkChatHeader: some View {
        DarkTranscriptHeader(
            title: chatTitle,
            subtitle: "\(selectedAgent?.name ?? "Agent") · \(selectedAgent?.hostName ?? "My machine")",
            isLive: isStreaming,
            onBack: { Haptics.selection(); resetForNewChat() },
            onWorkspace: { Haptics.selection(); onOpenWorkspace(selectedAgent) },
            onNew: { Haptics.selection(); resetForNewChat() },
            shareText: { transcriptText() },
            onSSHFeatures: { Haptics.selection(); showSSHFeatures = true }
        )
    }

    @ViewBuilder
    private func assistantTurn(for turn: ChatTurn) -> some View {
        let run = runOutputStore.run(turn.runId)
        // Only the LAST turn is "live" (drives the HUD/streaming + error chrome);
        // earlier turns render their final text statically.
        let isLast = activeRun?.runId == turn.runId
        // Read these UNCONDITIONALLY (not nested inside an else-if a populated
        // `run` would short-circuit) for two reasons: (1) an escalation almost
        // always happens mid-run, after the agent has already streamed some
        // output, so gating the card on "no output yet" meant it could never
        // show for a real conversation; (2) `@Observable` only re-renders this
        // view for properties actually read during body evaluation — a branch
        // that's never reached never subscribes, so `inboxViewModel.approvals`
        // updating later wouldn't even trigger a re-render. Appending the card
        // below existing output (instead of being mutually exclusive with it)
        // fixes both: the transcript keeps what already streamed AND shows the
        // gate the instant it appears.
        let livePendingApproval = (isLast && isAwaitingApproval) ? pendingApproval : nil
        let liveDeniedApproval = (isLast && isAwaitingApproval && livePendingApproval == nil) ? deniedApproval : nil

        VStack(alignment: .leading, spacing: 10) {
            if isLast && isErrorState {
                DSTypedErrorCard(error: .runFailed(""), onPrimary: nil, onSecondary: nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let run, !run.text.isEmpty || !run.blocks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    // A turn with command/tool blocks is a terminal turn: its streamed
                    // output (run.text) belongs in the dark macOS-window card, one per
                    // command. A turn with no blocks is a plain reply — show its prose
                    // as a normal left-aligned bubble.
                    if run.blocks.isEmpty {
                        if !run.text.isEmpty {
                            DarkAssistantBubble(run.text, author: agentLabel)
                        }
                    } else {
                        ForEach(Array(run.blocks.enumerated()), id: \.element.id) { index, block in
                            DarkTerminalBlockCard(
                                host: selectedAgent?.hostName ?? "My machine",
                                command: blockCommand(block),
                                // The run's combined output stream isn't split per block;
                                // attach it to the last (most recent) command card.
                                output: index == run.blocks.count - 1 ? run.text : "",
                                state: isLast && isErrorState ? .error : (block.status == .running ? .running : .done),
                                isShellSession: DarkTerminalBlockCard.isShellToolName(block.toolName)
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    persistedArtifacts(for: turn.runId)
                }
                .transition(.opacity)
            } else if livePendingApproval == nil && liveDeniedApproval == nil {
                // No output yet and no gate to show — the agent is working. Calm
                // typing indicator instead of the old pixel-grid box; it morphs
                // into the reply when text lands.
                DarkTypingIndicator()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            // Appended below whatever the run already produced, so an escalation
            // that fires after output has started streaming is never hidden.
            if let approval = livePendingApproval {
                inlineApprovalCard(for: approval)
                    .transition(.opacity)
            } else if let denied = liveDeniedApproval {
                // The user denied this action — show it plainly instead of a typing
                // dot that reads as "still working". The agent was stopped server-side.
                deniedCard(for: denied)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func deniedCard(for approval: Approval) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "hand.raised.slash.fill")
                .font(.dsSansPt(15, weight: .semibold))
                .foregroundStyle(t.danger)
            VStack(alignment: .leading, spacing: 3) {
                Text(approval.decision == .expired ? "Timed out — blocked" : "You denied this")
                    .font(.dsSansPt(14, weight: .semibold))
                    .foregroundStyle(t.text)
                Text("The agent was stopped before it ran \(approval.toolName ?? "this action"). Nothing was changed.")
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
                if let cmd = approval.command, !cmd.isEmpty {
                    Text(cmd)
                        .font(.dsMonoPt(11.5))
                        .foregroundStyle(t.text4)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: t.r3, style: .continuous).strokeBorder(t.danger.opacity(0.4), lineWidth: 1))
    }

    @ViewBuilder
    private func inlineApprovalCard(for approval: Approval) -> some View {
        let summary = ApprovalSummary.derive(from: approval)
        InboxApprovalCard(
            agentKey: agentKeyForSource(approval.agent),
            agentName: agentNameForSource(approval.agent),
            timeLabel: approval.createdAt.formatted(date: .omitted, time: .shortened),
            question: approval.kind == .askQuestion ? approval.question : summary.headline,
            toolName: approval.toolName,
            args: (approval.command ?? approval.toolInput).map { Redactor.shared.redact($0).redacted },
            risk: approval.risk.rawValue,
            onDeny: {
                Haptics.warning()
                // Keep isAwaitingApproval set so the transcript swaps to the denied
                // card (driven by the approval's resolved decision), not a typing dot.
                onDecideApproval(approval.id, .rejected)
            },
            onApprove: {
                Haptics.success()
                isAwaitingApproval = false
                onDecideApproval(approval.id, .approved)
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func agentKeyForSource(_ source: Approval.AgentSource) -> AgentKey {
        switch source {
        case .claudeCode: return .claudeCode
        case .codex:      return .codex
        case .cursor:     return .cursor
        case .opencode:   return .opencode
        case .devin:      return .devin
        case .unknown:    return .unknown
        }
    }

    private func agentNameForSource(_ source: Approval.AgentSource) -> String {
        switch source {
        case .claudeCode: "Claude Code"
        case .codex:      "Codex"
        case .cursor:     "Cursor"
        case .opencode:   "OpenCode"
        case .devin:      "Devin"
        case .unknown:    "Agent"
        }
    }

    /// Extract a human command string from a relay tool block's input JSON.
    private func blockCommand(_ block: RunOutputStore.ToolBlock) -> String {
        guard let data = block.inputJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return block.toolName }
        if let cmd = json["command"] as? String { return cmd }
        if let path = json["path"] as? String { return path }
        return block.toolName
    }

    @ViewBuilder
    private func persistedArtifacts(for runID: String) -> some View {
        let artifacts = artifactsByRun[runID] ?? []
        if !artifacts.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("RUN ARTIFACTS")
                    .font(.dsMonoPt(9, weight: .medium))
                    .tracking(0.9)
                    .foregroundStyle(t.text4)
                ForEach(artifacts) { artifact in
                    ChatArtifactCard(artifact: artifact) {
                        Haptics.selection()
                        selectedArtifact = artifact
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Bottom bar (compose toolbar OR live run controls)

    @ViewBuilder
    private var bottomBar: some View {
        if activeRun != nil, let controlStore {
            VStack(spacing: 0) {
                // Terminal: one slim status+regenerate line, then the composer is the
                // primary element. Live: the composer plus the Stop/Pause/Budget
                // controls. The old heavy "Run complete" filled bar + a separate
                // Regenerate row read as cluttered against the short transcript.
                if runIsTerminal {
                    terminalStatusRow
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                }
                RunFollowUpBar(
                    text: $followUpText,
                    isErrorState: isErrorState,
                    onSend: { followUp in Task { await sendFollowUp(followUp) } }
                )
                .padding(.horizontal, 18)
                .padding(.top, runIsTerminal ? 0 : 12)
                .padding(.bottom, runIsTerminal ? 12 : 0)
                if !runIsTerminal {
                    RunControlBar(
                        store: controlStore,
                        isTerminal: false,
                        failed: false,
                        exitCode: nil,
                        onStop: { confirmStop = true },
                        onShowBudget: { showBudgetSheet = true }
                    )
                    .padding(.top, 12)
                }
            }
            .background(t.bg.opacity(0.96).ignoresSafeArea(edges: .bottom))
        } else {
            bottomToolbar
        }
    }

    /// Slim "run finished" line: a status dot + label on the left, Regenerate as a
    /// quiet trailing action. Replaces the old full-width filled status bar.
    private var terminalStatusRow: some View {
        let failed = currentRun?.status == "failed"
        return HStack(spacing: 7) {
            Image(systemName: failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(failed ? t.termErr : t.termPrompt)
            Text(failed
                 ? "Run failed\(currentRun?.exitCode.map { " · exit \($0)" } ?? "")"
                 : "Run complete")
                .font(.dsMonoPt(12, weight: .medium))
                .foregroundStyle(t.text3)
            Spacer(minLength: 8)
            if !turns.isEmpty {
                Button {
                    Haptics.selection()
                    Task { await regenerateLast() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Regenerate")
                            .font(.dsSansPt(12.5, weight: .semibold))
                    }
                    .foregroundStyle(t.text2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Regenerate the last response")
            }
        }
    }

    private var selectedAgent: DispatchAgent? { agents.first { $0.id == selectedAgentID } }

    private var agentLabel: String {
        guard let agent = selectedAgent else { return "Pick agent" }
        let vendor = agent.vendor
        switch vendor {
        case "claudeCode": return "Claude"
        case "codex":      return "Codex"
        case "opencode":   return "opencode"
        case "kimi":       return "Kimi"
        default:           return agent.name
        }
    }

    private var machineLabel: String {
        selectedAgent?.hostName ?? selectedAgent?.name ?? "No host"
    }

    /// The directory the run launches in: an explicitly-picked project, else the
    /// selected agent's default cwd.
    private var effectiveCwd: String {
        selectedCwd.isEmpty ? (selectedAgent?.cwd ?? "~") : selectedCwd
    }

    private func displayPath(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private var workspaceLabel: String {
        let p = displayPath(effectiveCwd)
        return p.isEmpty ? "~" : p
    }

    private func lastPathComponent(_ path: String) -> String {
        let shown = displayPath(path)
        let last = (shown as NSString).lastPathComponent
        return last.isEmpty ? shown : last
    }

    private var modelShortLabel: String {
        selectedModel.isEmpty ? "Auto" : ModelCatalog.label(for: selectedModel)
    }

    /// The composer pill's full text: machine · workspace · model. Reads left to
    /// right in priority order — if it doesn't fit, the workspace segment (the
    /// middle one) drops first via `contextPillCompactText`, same truncation-priority
    /// pattern as `LancerHomeView.approvalSubtitle` (which drops its lowest-priority
    /// segment first), just driven by available width instead of Dynamic Type size.
    private var contextPillFullText: String {
        "\(machineLabel) · \(lastPathComponent(effectiveCwd)) · \(modelShortLabel)"
    }

    private var contextPillCompactText: String {
        "\(machineLabel) · \(modelShortLabel)"
    }

    /// Distinct known project directories across the connected agents, selected
    /// agent's cwd first — the quick-pick list in the Project drawer.
    private var projectDirs: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        if let sel = selectedAgent, !sel.cwd.isEmpty {
            seen.insert(sel.cwd); ordered.append(sel.cwd)
        }
        for agent in agents where !agent.cwd.isEmpty {
            if seen.insert(agent.cwd).inserted { ordered.append(agent.cwd) }
        }
        // Saved custom paths the user typed before — reusable without retyping.
        for path in recentProjectPaths where seen.insert(path).inserted {
            ordered.append(path)
        }
        return ordered
    }

    private var canSend: Bool {
        !isSending && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedAgent != nil && !(selectedAgent?.isOffline ?? true)
    }

    private var bottomToolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Agent chip
                Button { showContextPicker = true } label: {
                    HStack(spacing: 5) {
                        DSStatusDot(tone: .accent, size: 7)
                        Text(agentLabel)
                            .font(.dsSansPt(13, weight: .semibold))
                            .foregroundStyle(t.text)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(t.surface, in: Capsule())
                }
                .buttonStyle(.plain)

                // Machine \u{00B7} dir chip
                Button { showContextPicker = true } label: {
                    Text(machineLabel)
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.text3)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(t.surface, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                // Options toggle
                Button { withAnimation { showOptions.toggle() } } label: {
                    Text("Options")
                        .font(.dsSansPt(12, weight: .medium))
                        .foregroundStyle(showOptions ? t.text : t.text3)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(showOptions ? t.surface : t.bg, in: Capsule())
                }
                .buttonStyle(.plain)

                // Send
                Button {
                    Task { await sendCurrentPrompt() }
                } label: {
                    DSIconView(.send, size: 16, color: canSend ? t.accentFg : t.text4)
                        .frame(width: 40, height: 40)
                        .background(canSend ? t.accent : t.surface2, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(t.bg.ignoresSafeArea(edges: .bottom))
        }
    }

    // MARK: - Resume last selection

    /// Restores the last-used machine/workspace/model on New Chat entry instead of
    /// always defaulting to "first online agent". Falls back to today's default
    /// picking logic if the persisted machine/agent no longer exists or is offline.
    private func restoreLastSelectionOrDefault() {
        guard selectedAgentID.isEmpty else { return }
        if let agent = restoreAgent(machineKey: lastMachineID, modelID: lastModelID) {
            selectedAgentID = agent.id
            if !lastModelID.isEmpty, ModelCatalog.vendor(forModelID: lastModelID) == agent.vendor {
                selectedModel = lastModelID
            }
            if !lastWorkspacePath.isEmpty {
                selectedCwd = lastWorkspacePath
            }
        } else if let first = agents.first(where: { !$0.isOffline }) {
            selectedAgentID = first.id
        }
    }

    /// Finds an online agent on the persisted machine, preferring the one whose
    /// vendor matches the persisted model id (so a Codex model restores the Codex
    /// agent, not just any agent on that host).
    private func restoreAgent(machineKey: String, modelID: String) -> DispatchAgent? {
        guard !machineKey.isEmpty else { return nil }
        let candidates = agents.filter { ($0.hostID ?? $0.hostName ?? "") == machineKey && !$0.isOffline }
        guard !candidates.isEmpty else { return nil }
        if !modelID.isEmpty, let vendor = ModelCatalog.vendor(forModelID: modelID) {
            return candidates.first(where: { $0.vendor == vendor }) ?? candidates.first
        }
        return candidates.first
    }

    /// Persists the current machine/workspace/model so the next New Chat entry
    /// resumes this context.
    private func persistSelection() {
        lastMachineID = selectedAgent?.hostID ?? selectedAgent?.hostName ?? ""
        lastWorkspacePath = selectedCwd
        lastModelID = selectedModel
    }

    // MARK: - Actions

    private func sendCurrentPrompt() async {
        guard let agent = selectedAgent, canSend else { return }
        isSending = true
        defer { isSending = false }
        let budget = Double(budgetText.trimmingCharacters(in: .whitespacesAndNewlines))
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = selectedModel.isEmpty ? nil : selectedModel
        let cwd = effectiveCwd
        let outcome = await onDispatch(agent.id, cwd, trimmedPrompt, budget, model)
        switch outcome {
        case .started(let run):
            chatTitle = titleFromPrompt(trimmedPrompt)
            activeRun = run
            turns = [ChatTurn(prompt: trimmedPrompt, runId: run.runId)]
            controlStore = RunControlStore(channel: run.channel, runId: run.runId)
            prompt = ""
            selectedModel = ""
            budgetText = ""
            showOptions = false
            // Surface this run on the Lock Screen / Dynamic Island, mirroring
            // SessionViewModel's SSH-connect flow (SessionViewModel.swift ~328) —
            // this is the relay-dispatch path (V1's primary transport; "the phone
            // never holds an SSH session in V1" per ARCHITECTURE.md §0.1), which
            // previously never started a Live Activity at all, so every relay-
            // dispatched chat was invisible on the Lock Screen/Island regardless
            // of Live Activities being otherwise fully implemented and working.
            if #available(iOS 16.2, *) {
                let key = run.runId
                liveActivityKey = key
                Task {
                    await LancerLiveActivityManager.shared.start(
                        hostID: agent.hostID ?? agent.id,
                        hostName: agent.hostName ?? agent.name,
                        activityKey: key,
                        deviceSessionID: DeviceIdentity.sessionID(),
                        status: "running",
                        agentName: agent.vendor.isEmpty ? agent.name : agent.vendor
                    )
                }
            }
            // Persist conversation + turn
            if let chatRepo {
                Task {
                    // Persist the daemon-resolved absolute cwd (run.cwd), not the raw
                    // local `cwd` — a fresh relay dispatch's local value may still be
                    // the literal "~", which would silently fail to group/continue as
                    // the same project as a terminal session in the same real directory.
                    let conv = try? await chatRepo.createConversation(
                        title: chatTitle, agentID: agent.vendor.isEmpty ? agent.name : agent.vendor,
                        hostName: agent.hostName ?? agent.name, hostID: agent.hostID, cwd: run.cwd
                    )
                    conversationID = conv?.id
                    _ = try? await chatRepo.appendTurn(
                        conversationID: conv?.id ?? "", prompt: trimmedPrompt, runID: run.runId
                    )
                }
            }
        case .blocked(let message):
            // Empty message == benign supersede (a newer send replaced this one).
            if !message.isEmpty { dispatchErrorMessage = message }
        }
    }

    /// Continue the conversation: re-launch under a NEW runId via the run's channel,
    /// re-passing the daemon's policy + budget gates, then append the continued turn.
    private func sendFollowUp(_ followUp: String) async {
        let trimmed = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending, let active = activeRun else { return }
        isSending = true
        defer { isSending = false }
        followUpText = ""
        // Fresh turn — clear any prior awaiting/denied state from the last approval.
        isAwaitingApproval = false
        do {
            let result = try await active.channel.continueRun(runId: active.runId, prompt: trimmed)
            switch result.status {
            case "started":
                guard let newRunId = result.startedRunId else {
                    dispatchErrorMessage = result.message ?? "Couldn't continue the run."
                    return
                }
                runOutputStore.register(runId: newRunId)
                let continued = ActiveChatRun(
                    runId: newRunId,
                    channel: active.channel,
                    title: active.title,
                    subtitle: trimmed,
                    cwd: result.cwd ?? active.cwd
                )
                activeRun = continued
                turns.append(ChatTurn(prompt: trimmed, runId: newRunId))
                controlStore = RunControlStore(channel: continued.channel, runId: newRunId)
                // Reflect the new turn on the SAME continuous Live Activity — keyed
                // by the thread's original liveActivityKey, not the new runId, so a
                // multi-turn conversation stays one Activity instead of spawning a
                // new one per follow-up.
                if #available(iOS 16.2, *), let key = liveActivityKey {
                    Task { await LancerLiveActivityManager.shared.update(activityKey: key, status: "running") }
                }
                // Persist follow-up turn
                if let chatRepo, let convID = conversationID {
                    Task {
                        _ = try? await chatRepo.appendTurn(
                            conversationID: convID, prompt: trimmed, runID: newRunId
                        )
                    }
                }
            case "denied":
                dispatchErrorMessage = "Blocked by policy\(result.rule.map { " (\($0))" } ?? "")."
            case "needsApproval":
                isAwaitingApproval = true
            case "budgetExceeded":
                dispatchErrorMessage = result.message ?? "Daily budget cap reached."
            default:
                dispatchErrorMessage = result.message ?? "Couldn't continue the run."
            }
        } catch {
            // Benign supersede (a newer follow-up replaced this one) — stay quiet.
            if case E2EError.superseded = error { return }
            dispatchErrorMessage = "Follow-up failed: \(error.localizedDescription)"
        }
    }

    /// Regenerate the last response: re-run the most recent prompt as a fresh turn
    /// (continues under a new runId, re-passing policy + budget). Same plumbing as a
    /// follow-up, with the previous prompt text.
    private func regenerateLast() async {
        guard let last = turns.last else { return }
        await sendFollowUp(last.prompt)
    }

    /// Plain-text export of the live conversation, shared via the header.
    private func transcriptText() -> String {
        var out = "# \(chatTitle)\n\(selectedAgent?.name ?? "Agent") · \(selectedAgent?.hostName ?? "My machine")\n\n"
        for turn in turns {
            let reply = runOutputStore.run(turn.runId)?.text ?? ""
            out += "## You\n\(turn.prompt)\n\n## \(agentLabel)\n\(reply)\n\n"
        }
        return out
    }

    private func resetForNewChat() {
        activeRun = nil
        controlStore = nil
        chatTitle = "new task"
        turns = []
        prompt = ""
        followUpText = ""
        dispatchErrorMessage = nil
        isAwaitingApproval = false
        conversationID = nil
        artifactsByRun = [:]
        selectedArtifact = nil
        showOptions = false
    }

    private func loadArtifacts() async {
        guard let repo = chatRepo, let conversationID else { return }
        let artifacts = (try? await repo.artifacts(conversationID: conversationID)) ?? []
        await MainActor.run {
            artifactsByRun = Dictionary(grouping: artifacts, by: \.runID)
        }
    }

    /// Cheap heuristic title: first few words of the prompt, cleaned of whitespace runs.
    private func titleFromPrompt(_ raw: String) -> String {
        let words = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return "new chat" }
        let truncatedWords = words.prefix(6).joined(separator: " ")
        if truncatedWords.count > 48 {
            return String(truncatedWords.prefix(45)) + "\u{2026}"
        }
        return words.count > 6 ? truncatedWords + "\u{2026}" : truncatedWords
    }

    // MARK: - Budget field (idle compose state only)

    private var budgetField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Budget cap")
                .font(.dsSansPt(13, weight: .semibold))
                .foregroundStyle(t.text3)
            HStack(spacing: 6) {
                Text("$").font(.dsMonoPt(13)).foregroundStyle(t.text3)
                TextField("None", text: $budgetText)
                    .font(.dsMonoPt(13))
                    .foregroundStyle(t.text)
                    .keyboardType(.decimalPad)
            }
            .padding(.horizontal, 13)
            .frame(height: 46)
            .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        }
        .padding(14)
        .background(t.surface, in: RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.border.opacity(0.65), lineWidth: 1)
        )
    }

    private var groupedAgents: [(String, [DispatchAgent])] {
        // Group by the machine's real name. Fall back to a neutral label (never the
        // transport word "Relay") until the daemon reports its hostname.
        Dictionary(grouping: agents, by: { $0.hostName ?? "My machine" })
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    // MARK: - Context picker (Machine / Workspace / Model — one consolidated sheet)

    /// One combined sheet replacing the old separate Machine, Agent, and Model
    /// pickers: three always-visible sections (never a stepped flow). Rows don't
    /// auto-dismiss on tap — the user can adjust more than one section before
    /// tapping Done, mirroring `chat-context/b/page.tsx`.
    private var contextPickerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                contextSection("Machine") {
                    ForEach(groupedAgents, id: \.0) { machine, agentsOnMachine in
                        contextRow(
                            icon: .server,
                            label: machine,
                            sub: "\(agentsOnMachine.count) agent\(agentsOnMachine.count == 1 ? "" : "s")",
                            isSelected: machine == machineLabel,
                            isDisabled: agentsOnMachine.allSatisfy(\.isOffline)
                        ) {
                            selectMachine(machine, agentsOnMachine)
                        }
                    }
                }

                contextSection("Workspace") {
                    ForEach(projectDirs, id: \.self) { dir in
                        contextRow(
                            icon: .folder,
                            label: lastPathComponent(dir),
                            sub: displayPath(dir),
                            isSelected: dir == effectiveCwd,
                            isDisabled: false
                        ) {
                            selectWorkspace(dir)
                        }
                    }
                    customWorkspaceEntry
                }

                contextSection("Model") {
                    ForEach(scopedAgentsForModel) { agent in
                        modelAgentGroup(agent)
                    }
                }

                Button {
                    Haptics.selection()
                    showContextPicker = false
                } label: {
                    Text("Done")
                        .font(.dsSansPt(16, weight: .semibold))
                        .foregroundStyle(t.accentFg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(t.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Done configuring the run")
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func contextSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.dsMonoPt(10.5, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(t.text4)
            VStack(spacing: 6) { content() }
        }
    }

    /// Shared row style for all three sections: icon + label + sub-label + a
    /// checkmark on the selected row. Offline/unavailable rows are `.disabled` AND
    /// visibly dimmed — never just tappable-but-inert.
    private func contextRow(
        icon: DSIcon,
        label: String,
        sub: String?,
        isSelected: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 12) {
                DSIconView(icon, size: 15, color: isDisabled ? t.text4 : (isSelected ? t.accent : t.text3))
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.dsSansPt(14, weight: .medium))
                        .foregroundStyle(isDisabled ? t.text4 : t.text)
                        .lineLimit(1)
                    if let sub, !sub.isEmpty {
                        Text(sub)
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text4)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    DSIconView(.check, size: 14, color: t.accent)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: sub == nil ? 48 : 56)
            .background(isSelected ? t.accentSoft : t.surface, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                    .strokeBorder(isSelected ? t.accent.opacity(0.6) : t.border.opacity(0.65), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .opacity(isDisabled ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    /// One agent's model group within the Model section: an "Auto" row plus one
    /// row per `ModelCatalog` model for that agent's vendor. Selecting any row here
    /// sets both the model AND the agent — this is how Model absorbs the old Agent
    /// picker's job instead of duplicating it as a fourth section.
    private func modelAgentGroup(_ agent: DispatchAgent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(agent.name)
                .font(.dsMonoPt(10.5, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(t.text4)
                .padding(.horizontal, 4)
            VStack(spacing: 6) {
                contextRow(
                    icon: .sparkles,
                    label: "Auto (agent default)",
                    sub: nil,
                    isSelected: agent.id == selectedAgentID && selectedModel.isEmpty,
                    isDisabled: agent.isOffline
                ) {
                    selectModel(agent: agent, modelID: "")
                }
                ForEach(ModelCatalog.models(for: agent.vendor), id: \.id) { model in
                    contextRow(
                        icon: .sparkles,
                        label: model.label,
                        sub: nil,
                        isSelected: agent.id == selectedAgentID && selectedModel == model.id,
                        isDisabled: agent.isOffline
                    ) {
                        selectModel(agent: agent, modelID: model.id)
                    }
                }
            }
            .padding(6)
            .background(t.surface.opacity(0.76), in: RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border.opacity(0.65), lineWidth: 1)
            )
        }
    }

    /// Agents to list in the Model section, scoped to the currently-selected
    /// machine (mirrors the old agent picker's scoping). Falls back to every agent
    /// if nothing is selected yet (shouldn't happen in practice — `onAppear`
    /// always picks a default or restores one before the sheet can open).
    private var scopedAgentsForModel: [DispatchAgent] {
        groupedAgents.first { $0.0 == machineLabel }?.1 ?? agents
    }

    private func selectMachine(_ machine: String, _ agentsOnMachine: [DispatchAgent]) {
        guard let pick = agentsOnMachine.first(where: { !$0.isOffline }) else { return }
        selectedAgentID = pick.id
        // A new machine invalidates both the workspace default and the model
        // selection (models are vendor-specific) — reset both, same as today's
        // machine-picker behavior for cwd.
        selectedCwd = ""
        selectedModel = ""
        persistSelection()
    }

    private func selectWorkspace(_ dir: String) {
        selectedCwd = dir
        persistSelection()
    }

    private func selectModel(agent: DispatchAgent, modelID: String) {
        selectedAgentID = agent.id
        selectedModel = modelID
        persistSelection()
    }

    private var customWorkspaceEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom path")
                .font(.dsSansPt(12, weight: .medium))
                .foregroundStyle(t.text3)
            HStack(spacing: 8) {
                TextField("~/projects/my-app", text: $customCwd)
                    .font(.dsMonoPt(13))
                    .foregroundStyle(t.text)
                    .tint(t.accent)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { useCustomCwd() }
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                DSButton("Use", variant: .secondary, size: .sm) { useCustomCwd() }
                    .disabled(customCwd.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.top, 4)
    }

    private func useCustomCwd() {
        let trimmed = customCwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Haptics.selection()
        selectedCwd = trimmed
        rememberProjectPath(trimmed)
        customCwd = ""
        persistSelection()
    }

    /// Recently-used custom paths (newest first), persisted across launches.
    private var recentProjectPaths: [String] {
        recentProjectPathsRaw.split(separator: "\n").map(String.init)
    }

    /// Save a custom path to the front of the recents (deduped, capped at 8).
    private func rememberProjectPath(_ path: String) {
        var recents = recentProjectPaths.filter { $0 != path }
        recents.insert(path, at: 0)
        recentProjectPathsRaw = recents.prefix(8).joined(separator: "\n")
    }
}

#endif
