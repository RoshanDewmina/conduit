#if os(iOS)
import SwiftUI
import DesignSystem
import SessionFeature
import AgentKit
import PersistenceKit

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

    @State private var prompt: String = ""
    @State private var selectedAgentID: String = ""
    /// Empty ⇒ use the selected agent's default cwd. A non-empty value is an explicit
    /// project directory the user picked for this run (the Omnara "in [workspace]" slot).
    @State private var selectedCwd: String = ""
    @State private var customCwd: String = ""
    @State private var showAgentPicker = false
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
    @State private var dispatchErrorMessage: String?

    // Persistence
    @State private var conversationID: String?
    @State private var artifactsByRun: [String: [ChatArtifact]] = [:]
    @State private var selectedArtifact: ChatArtifact?
    @FocusState private var composeFocused: Bool

    @Environment(\.conduitTokens) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        agents: [DispatchAgent],
        runOutputStore: RunOutputStore,
        chatRepo: ChatConversationRepository? = nil,
        fleetStore: FleetStore,
        onDispatch: @escaping (_ agentID: String, _ cwd: String, _ prompt: String, _ budgetUSD: Double?, _ model: String?) async -> ChatDispatchOutcome,
        onNewTask: @escaping () -> Void,
        onOpenWorkspace: @escaping (DispatchAgent?) -> Void = { _ in }
    ) {
        self.agents = agents
        self.runOutputStore = runOutputStore
        self.chatRepo = chatRepo
        self.fleetStore = fleetStore
        self.onDispatch = onDispatch
        self.onNewTask = onNewTask
        self.onOpenWorkspace = onOpenWorkspace
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
        .background(t.bg.ignoresSafeArea())
        .onAppear {
            if selectedAgentID.isEmpty, let first = agents.first(where: { !$0.isOffline }) {
                selectedAgentID = first.id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .conduitChatArtifactPersisted)) { note in
            guard let cid = note.userInfo?["conversationID"] as? String, cid == conversationID else { return }
            Task { await loadArtifacts() }
        }
        .bottomDrawer(
            isPresented: $showAgentPicker,
            title: "Choose agent",
            subtitle: "Choose where this work should run.",
            detents: [.medium, .large]
        ) {
            agentPickerContent
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
            isPresented: $showComposer,
            title: "New chat",
            subtitle: "Describe the work. Conduit routes it through policy before anything runs.",
            detents: [.medium, .large]
        ) {
            composerDrawerContent
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

    /// The idle New Chat surface: a calm title and a single entry point that opens
    /// the composer as a bottom drawer. The fields live inside the drawer so the
    /// landing stays quiet and there's no full-page form to scroll.
    private var composerLanding: some View {
        VStack(spacing: 20) {
            Spacer()
            VStack(spacing: 10) {
                DSIconView(.sparkles, size: 30, color: t.accent)
                Text("New chat")
                    .font(.dsDisplayPt(28, weight: .bold))
                    .foregroundStyle(t.text)
                Text("Describe the work. Conduit routes it through policy before anything runs.")
                    .font(.dsSansPt(14))
                    .foregroundStyle(t.text3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
            }
            Button {
                Haptics.selection()
                showComposer = true
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                    Text("New chat")
                        .font(.dsSansPt(16, weight: .semibold))
                }
                .foregroundStyle(t.accentFg)
                .padding(.horizontal, 22)
                .frame(height: 52)
                .background(t.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start a new chat")
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }

    /// The composer fields, presented inside the bottom drawer. Same controls and
    /// wiring as before — prompt, Agent/Host/Project pills, Options, Send — just
    /// hosted in a native sheet (presentationDetents) instead of a full page.
    private var composerDrawerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Describe a task or just say hi…", text: $prompt, axis: .vertical)
                    .font(.dsSansPt(16))
                    .foregroundStyle(t.text)
                    .tint(t.accent)
                    .lineLimit(4...12)
                    .focused($composeFocused)
                    .padding(14)
                    .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(t.border.opacity(0.72), lineWidth: 1)
                    )

                HStack(spacing: 10) {
                    composerPill(
                        title: agentLabel,
                        subtitle: "Agent",
                        icon: .sparkles,
                        tone: selectedAgent?.isOffline == true ? t.text4 : t.accent
                    ) {
                        showAgentPicker = true
                    }
                    composerPill(
                        title: machineLabel,
                        subtitle: "Host",
                        icon: .server,
                        tone: t.text3
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

                Button {
                    withAnimation(ConduitMotion.resolved(.smooth(duration: 0.28, extraBounce: 0), reduceMotion: reduceMotion)) {
                        showOptions.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("Options")
                            .font(.dsSansPt(14, weight: .semibold))
                        Image(systemName: showOptions ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(showOptions ? t.text : t.text3)
                }
                .buttonStyle(.plain)

                if showOptions {
                    optionsPanel
                }

                Button {
                    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    composeFocused = false
                    showComposer = false
                    Task { await sendCurrentPrompt() }
                } label: {
                    HStack(spacing: 9) {
                        Text("Send")
                            .font(.dsSansPt(16, weight: .semibold))
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(canSend ? t.accentFg : t.text4)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(canSend ? t.accent : t.surfaceSunk, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send chat")
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
    }

    // Transcript chrome follows the app theme; only the terminal output card is
    // intentionally dark so an active conversation doesn't create a second app skin.
    private var darkChatHeader: some View {
        DarkTranscriptHeader(
            title: chatTitle,
            subtitle: "\(selectedAgent?.name ?? "Agent") · \(selectedAgent?.hostName ?? "relay")",
            isLive: isStreaming,
            onBack: { Haptics.selection(); resetForNewChat() },
            onWorkspace: { Haptics.selection(); onOpenWorkspace(selectedAgent) },
            onNew: { Haptics.selection(); resetForNewChat() }
        )
    }

    @ViewBuilder
    private func assistantTurn(for turn: ChatTurn) -> some View {
        let run = runOutputStore.run(turn.runId)
        // Only the LAST turn is "live" (drives the HUD/streaming + error chrome);
        // earlier turns render their final text statically.
        let isLast = activeRun?.runId == turn.runId
        if isLast && isErrorState {
            DSTypedErrorCard(error: .other("Run failed"), onPrimary: nil, onSecondary: nil)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let run, !run.text.isEmpty || !run.blocks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if isLast && isStreaming {
                    HStack(spacing: 5) {
                        PixelBox(state: agentState, size: 9, subdivisions: 2)
                        Text(agentState == .thinking ? "thinking\u{2026}" : "streaming")
                            .font(.dsSansPt(12, weight: .medium))
                            .foregroundStyle(t.text4)
                    }
                    .padding(.bottom, 2)
                }
                // A turn with command/tool blocks is a terminal turn: its streamed
                // output (run.text) belongs in the dark macOS-window card, one per
                // command. A turn with no blocks is a plain reply — show its prose
                // as a normal left-aligned bubble.
                if run.blocks.isEmpty {
                    if !run.text.isEmpty {
                        DarkAssistantBubble(run.text)
                    }
                } else {
                    ForEach(Array(run.blocks.enumerated()), id: \.element.id) { index, block in
                        DarkTerminalBlockCard(
                            host: selectedAgent?.hostName ?? "relay",
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
        } else {
            HStack(spacing: 6) {
                PixelBox(state: .thinking, size: 10, subdivisions: 2)
                Text("thinking\u{2026}")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
            VStack(spacing: 10) {
                RunFollowUpBar(
                    text: $followUpText,
                    isErrorState: isErrorState,
                    onSend: { followUp in Task { await sendFollowUp(followUp) } }
                )
                .padding(.horizontal, 18)
                .padding(.top, 12)
                RunControlBar(
                    store: controlStore,
                    isTerminal: runIsTerminal,
                    failed: currentRun?.status == "failed",
                    exitCode: currentRun?.exitCode,
                    onStop: { confirmStop = true },
                    onShowBudget: { showBudgetSheet = true }
                )
            }
            .background(t.bg.opacity(0.96).ignoresSafeArea(edges: .bottom))
        } else {
            bottomToolbar
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
        return ordered
    }

    private var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedAgent != nil && !(selectedAgent?.isOffline ?? true)
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
            dispatchErrorMessage = message
        }
    }

    /// Continue the conversation: re-launch under a NEW runId via the run's channel,
    /// re-passing the daemon's policy + budget gates, then append the continued turn.
    private func sendFollowUp(_ followUp: String) async {
        let trimmed = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let active = activeRun else { return }
        followUpText = ""
        do {
            let result = try await active.channel.continueRun(runId: active.runId, prompt: trimmed)
            switch result.status {
            case "started":
                guard let newRunId = result.runId else {
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
                dispatchErrorMessage = "Awaiting your approval — check the Inbox."
            case "budgetExceeded":
                dispatchErrorMessage = result.message ?? "Daily budget cap reached."
            default:
                dispatchErrorMessage = result.message ?? "Couldn't continue the run."
            }
        } catch {
            dispatchErrorMessage = "Follow-up failed: \(error.localizedDescription)"
        }
    }

    private func resetForNewChat() {
        activeRun = nil
        controlStore = nil
        chatTitle = "new task"
        turns = []
        prompt = ""
        followUpText = ""
        dispatchErrorMessage = nil
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
                    if selectedAgent?.vendor == "claudeCode" || selectedAgent?.vendor == "openrouter" {
                        Button("Claude Sonnet 4") { selectedModel = "claude-sonnet-4" }
                        Button("Claude Haiku 4") { selectedModel = "claude-haiku-4" }
                    }
                    if selectedAgent?.vendor == "opencode" || selectedAgent?.vendor == "openrouter" {
                        Button("DeepSeek V4 Flash (free)") { selectedModel = "opencode/deepseek-v4-flash-free" }
                        Button("MiMo V2.5 (free)") { selectedModel = "opencode/mimo-v2.5-free" }
                    }
                    if selectedAgent?.vendor == "codex" || selectedAgent?.vendor == "openrouter" {
                        Button("GPT-5 Codex") { selectedModel = "openai/gpt-5-codex" }
                    }
                    if selectedAgent?.vendor == "kimi" || selectedAgent?.vendor == "openrouter" {
                        Button("Kimi K2.7 Code") { selectedModel = "kimi-code/kimi-for-coding" }
                    }
                    if selectedAgent?.vendor == "openrouter" {
                        Button("Gemini 2.5 Pro") { selectedModel = "google/gemini-2.5-pro" }
                    }
                } label: {
                    HStack {
                        Text(selectedModel.isEmpty ? "Auto (agent default)" : selectedModel)
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
        Dictionary(grouping: agents, by: { $0.hostName ?? "Relay" })
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
        showWorkspacePicker = false
    }

    private var agentPickerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(groupedAgents, id: \.0) { group in
                    agentPickerGroup(machine: group.0, agents: group.1)
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
