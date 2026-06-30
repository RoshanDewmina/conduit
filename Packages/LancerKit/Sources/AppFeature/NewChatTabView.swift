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
import SecurityKit

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
    @State private var showAgentPicker = false
    @State private var showMachinePicker = false
    @State private var showWorkspacePicker = false
    @State private var showComposer = false
    @State private var showOptions = false
    @State private var selectedModel: String = ""
    @State private var budgetText: String = ""

    // Inline conversation state — set once a dispatch starts; nil shows the
    // compose screen.
    @State private var activeRun: ActiveChatRun?
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
            case "/model", "/budget": showComposer = true
            case "/agent": showAgentPicker = true
            case "/workspace": customCwd = ""; showWorkspacePicker = true
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
        .onAppear {
            if selectedAgentID.isEmpty, let first = agents.first(where: { !$0.isOffline }) {
                selectedAgentID = first.id
            }
        }
        .task(id: selectedAgentID) { await refreshCommands() }
        .onChange(of: showComposer) { _, open in
            if open { Task { await refreshCommands() } }
        }
        .onChange(of: prompt) { _, _ in
            Task { await refreshFilesIfMentioning() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lancerChatArtifactPersisted)) { note in
            guard let cid = note.userInfo?["conversationID"] as? String, cid == conversationID else { return }
            Task { await loadArtifacts() }
        }
        .bottomDrawer(
            isPresented: $showAgentPicker,
            title: "Choose agent",
            subtitle: "Pick which agent runs on \(machineLabel).",
            detents: [.medium, .large]
        ) {
            agentPickerContent
        }
        .bottomDrawer(
            isPresented: $showMachinePicker,
            title: "Choose machine",
            subtitle: "Pick where this work runs.",
            detents: [.medium, .large]
        ) {
            machinePickerContent
        }
        .bottomDrawer(
            isPresented: $showWorkspacePicker,
            title: "Project",
            subtitle: "Where this run works. Defaults to the agent's directory.",
            detents: [.medium, .large]
        ) {
            workspacePickerContent
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
            title: "Run settings",
            subtitle: "Choose where this runs and which model to use.",
            detents: [.medium, .large]
        ) {
            runSettingsContent
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
                Button { showAgentPicker = true } label: {
                    HStack(spacing: 5) {
                        DSStatusDot(tone: selectedAgent?.isOffline == true ? .off : .accent, size: 7)
                        Text(agentLabel)
                            .font(.dsSansPt(12.5, weight: .semibold))
                            .foregroundStyle(t.text2)
                        Text("· \(machineLabel)")
                            .font(.dsSansPt(11.5))
                            .foregroundStyle(t.text4)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(t.surface, in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Button { showComposer = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(t.text3)
                        .frame(width: 32, height: 32)
                        .background(t.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Options — model, budget, project")
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 10)
        .background(t.bg.ignoresSafeArea(edges: .bottom))
    }

    /// Config-only sheet opened by the composer's settings control: choose the
    /// machine, agent, project directory, model, and budget for the run. The prompt
    /// and Send live on the inline composer landing — this sheet never duplicates
    /// them; it just configures where/how the next message runs and is dismissed.
    private var runSettingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    composerPill(
                        title: machineLabel,
                        subtitle: "Machine",
                        icon: .server,
                        tone: selectedAgent?.isOffline == true ? t.text4 : t.accent
                    ) {
                        showMachinePicker = true
                    }
                    composerPill(
                        title: agentLabel,
                        subtitle: "Agent",
                        icon: .sparkles,
                        tone: selectedAgent?.isOffline == true ? t.text4 : t.accent
                    ) {
                        showAgentPicker = true
                    }
                }

                composerPill(
                    title: workspaceLabel,
                    subtitle: "Project",
                    icon: .folder,
                    tone: t.text3
                ) {
                    customCwd = ""
                    showWorkspacePicker = true
                }

                optionsPanel

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
                .accessibilityLabel("Done configuring the run")
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Composer pill (Agent / Host control)

    private func composerPill(
        title: String,
        subtitle: String,
        icon: DSIcon,
        tone: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                DSIconView(icon, size: 15, color: tone)
                    .frame(width: 32, height: 32)
                    .background(t.surface2, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(subtitle)
                        .font(.dsSansPt(11, weight: .medium))
                        .foregroundStyle(t.text4)
                    Text(title)
                        .font(.dsSansPt(13, weight: .semibold))
                        .foregroundStyle(t.text2)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(t.text4)
            }
            .padding(.horizontal, 12)
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .background(t.surface, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                    .strokeBorder(t.border.opacity(0.65), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
                            state: isLast && isErrorState ? .error : (block.status == .running ? .running : .done)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                persistedArtifacts(for: turn.runId)
            }
            .transition(.opacity)
        } else if isLast, isAwaitingApproval, let approval = pendingApproval {
            inlineApprovalCard(for: approval)
                .transition(.opacity)
        } else if isLast, isAwaitingApproval, let denied = deniedApproval {
            // The user denied this action — show it plainly instead of a typing dot
            // that reads as "still working". The agent was stopped server-side.
            deniedCard(for: denied)
                .transition(.opacity)
        } else {
            // No output yet — the agent is working. Calm typing indicator instead
            // of the old pixel-grid box; it morphs into the reply when text lands.
            DarkTypingIndicator()
                .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
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
        let isCritical = approval.risk >= .critical
        InboxApprovalCard(
            agentKey: agentKeyForSource(approval.agent),
            agentName: agentNameForSource(approval.agent),
            timeLabel: approval.createdAt.formatted(date: .omitted, time: .shortened),
            question: approval.kind == .askQuestion ? approval.question : summary.headline,
            toolName: approval.toolName,
            args: approval.command ?? approval.toolInput,
            risk: approval.risk.rawValue,
            isCritical: isCritical,
            onDeny: {
                Haptics.warning()
                // Keep isAwaitingApproval set so the transcript swaps to the denied
                // card (driven by the approval's resolved decision), not a typing dot.
                onDecideApproval(approval.id, .rejected)
            },
            onApprove: {
                // Critical approvals must clear biometric auth before committing, same
                // gate InboxView's pendingCard/detailSheet already enforce — without this,
                // this inline chat-thread card was a single-tap bypass of that gate for
                // the same approval (it differs only in WHERE the user encounters it).
                Task {
                    if isCritical {
                        do { try await BiometricGate.shared.unlock(reason: "Authenticate to approve a critical action") }
                        catch {
                            if let ce = error as? LancerCore.LancerError, case .cancelled = ce { return }
                            Haptics.error()
                            return
                        }
                    }
                    Haptics.success()
                    isAwaitingApproval = false
                    onDecideApproval(approval.id, .approved)
                }
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
                Button { showAgentPicker = true } label: {
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
                Button { showAgentPicker = true } label: {
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
            // Persist conversation + turn
            if let chatRepo {
                Task {
                    let conv = try? await chatRepo.createConversation(
                        title: chatTitle, agentID: agent.vendor.isEmpty ? agent.name : agent.vendor,
                        hostName: agent.hostName ?? agent.name, hostID: agent.hostID, cwd: cwd
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
                    subtitle: trimmed
                )
                activeRun = continued
                turns.append(ChatTurn(prompt: trimmed, runId: newRunId))
                controlStore = RunControlStore(channel: continued.channel, runId: newRunId)
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

    // MARK: - Options panel (idle compose state only)

    private var optionsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Model")
                    .font(.dsSansPt(13, weight: .semibold))
                    .foregroundStyle(t.text3)
                Menu {
                    Button("Auto (agent default)") { selectedModel = "" }
                    ForEach(ModelCatalog.models(for: selectedAgent?.vendor ?? ""), id: \.id) { model in
                        Button(model.label) { selectedModel = model.id }
                    }
                } label: {
                    HStack {
                        Text(selectedModel.isEmpty ? "Auto (agent default)" : ModelCatalog.label(for: selectedModel))
                            .font(.dsSansPt(14, weight: .medium))
                            .foregroundStyle(t.text2)
                            .lineLimit(1)
                        Spacer()
                        DSIconView(.chevronDown, size: 12, color: t.text3)
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 46)
                    .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                }
            }
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

    // MARK: - Workspace (project directory) picker

    private var workspacePickerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !projectDirs.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(projectDirs, id: \.self) { dir in
                            workspaceRow(dir)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom path")
                        .font(.dsSansPt(13, weight: .semibold))
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
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
    }

    private func workspaceRow(_ dir: String) -> some View {
        let isSelected = dir == effectiveCwd
        return Button {
            Haptics.selection()
            selectedCwd = dir
            showWorkspacePicker = false
        } label: {
            HStack(spacing: 12) {
                DSIconView(.folder, size: 15, color: isSelected ? t.accent : t.text3)
                Text(displayPath(dir))
                    .font(.dsMonoPt(12.5))
                    .foregroundStyle(isSelected ? t.text : t.text2)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    DSIconView(.check, size: 15, color: t.accent)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(isSelected ? t.surface2 : t.surface, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func useCustomCwd() {
        let trimmed = customCwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Haptics.selection()
        selectedCwd = trimmed
        rememberProjectPath(trimmed)
        showWorkspacePicker = false
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

    /// Agent picker, scoped to the currently-selected machine: lists just that
    /// host's agents. If no machine is selected yet, shows all (grouped by machine).
    private var agentPickerContent: some View {
        let groups = groupedAgents
        let scoped = groups.first { $0.0 == machineLabel }.map { [$0] } ?? groups
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(scoped, id: \.0) { group in
                    agentPickerGroup(machine: group.0, agents: group.1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
    }

    /// Machine picker: one row per connected host. Choosing a machine selects its
    /// first available agent so the run is immediately dispatchable.
    private var machinePickerContent: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(groupedAgents, id: \.0) { machine, agents in
                    let firstOnline = agents.first { !$0.isOffline } ?? agents.first
                    let isSelected = machine == machineLabel
                    Button {
                        if let pick = firstOnline {
                            selectedAgentID = pick.id
                            selectedCwd = ""
                        }
                        showMachinePicker = false
                    } label: {
                        HStack(spacing: 12) {
                            DSIconView(.server, size: 16, color: isSelected ? t.accent : t.text3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(machine)
                                    .font(.dsSansPt(15, weight: .semibold))
                                    .foregroundStyle(t.text)
                                Text("\(agents.count) agent\(agents.count == 1 ? "" : "s")")
                                    .font(.dsMonoPt(11))
                                    .foregroundStyle(t.text4)
                            }
                            Spacer(minLength: 0)
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(t.accent)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isSelected ? t.accentSoft : t.surface, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                                .strokeBorder(isSelected ? t.accent : t.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
    }

    private func agentPickerGroup(machine: String, agents: [DispatchAgent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(machine)
                .font(.dsSansPt(15, weight: .semibold))
                .foregroundStyle(t.text2)
                .padding(.horizontal, 4)
            VStack(spacing: 6) {
                ForEach(agents) { agent in
                    agentPickerRow(agent)
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

    private func agentPickerRow(_ agent: DispatchAgent) -> some View {
        let isSelected = agent.id == selectedAgentID
        return Button {
            guard !agent.isOffline else { return }
            selectedAgentID = agent.id
            selectedCwd = ""
            showAgentPicker = false
        } label: {
            HStack(spacing: 12) {
                DSStatusDot(tone: agent.isOffline ? .off : .ok, size: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(agent.name)
                        .font(.dsSansPt(16, weight: .semibold))
                        .foregroundStyle(agent.isOffline ? t.text4 : t.text)
                    Text(agent.vendor.isEmpty ? agent.cwd : "\(agent.vendor) · \(agent.cwd)")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                        .lineLimit(1)
                }
                Spacer()
                if isSelected {
                    DSIconView(.check, size: 15, color: t.accent)
                        .frame(width: 30, height: 30)
                        .background(t.accentSoft, in: Circle())
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 64)
            .background(isSelected ? t.surface2 : t.surface, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(agent.isOffline)
    }
}

#endif
