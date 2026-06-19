#if os(iOS)
import SwiftUI
import DesignSystem
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
    let initialConversationID: String?

    @State private var prompt: String = ""
    @State private var isHistorical = false
    @State private var selectedAgentID: String = ""
    @State private var showAgentPicker = false
    @State private var showOptions = false
    @State private var selectedModel: String = ""
    @State private var budgetText: String = ""

    // Inline conversation state — set once a dispatch starts; nil shows the
    // compose screen.
    @State private var activeRun: ActiveChatRun?
    @State private var controlStore: RunControlStore?
    @State private var chatTitle: String = "new chat"
    @State private var sentPrompt: String = ""
    // One conversation = an ordered list of (prompt, runId) turns. The first is the
    // initial dispatch; each follow-up appends a new turn under a new runId.
    @State private var turns: [ChatTurn] = []
    @State private var followUpText: String = ""
    @State private var confirmStop = false
    @State private var showBudgetSheet = false
    @State private var dispatchErrorMessage: String?

    // Persistence
    @State private var conversationID: String?
    @State private var recentConversations: [ChatConversation] = []
    @State private var showComposer = false

    @Environment(\.conduitTokens) private var t

    public init(
        agents: [DispatchAgent],
        runOutputStore: RunOutputStore,
        chatRepo: ChatConversationRepository? = nil,
        fleetStore: FleetStore,
        onDispatch: @escaping (_ agentID: String, _ cwd: String, _ prompt: String, _ budgetUSD: Double?, _ model: String?) async -> ChatDispatchOutcome,
        onNewTask: @escaping () -> Void,
        onOpenWorkspace: @escaping (DispatchAgent?) -> Void = { _ in },
        initialConversationID: String? = nil
    ) {
        self.agents = agents
        self.runOutputStore = runOutputStore
        self.chatRepo = chatRepo
        self.fleetStore = fleetStore
        self.onDispatch = onDispatch
        self.onNewTask = onNewTask
        self.onOpenWorkspace = onOpenWorkspace
        self.initialConversationID = initialConversationID
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
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                if activeRun != nil || isHistorical {
                    chatHeader
                }
                if activeRun != nil || isHistorical {
                    ConversationScrollView(bottomID: "newchat-bottom", scrollKey: currentRun?.chunks.count ?? 0) {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(turns) { turn in
                                turnView(turn)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                    }
                } else if let repo = chatRepo {
                    SessionsListView(
                        chatRepo: repo,
                        fleetStore: fleetStore,
                        onOpenThread: { id in
                            Task { await loadConversation(id: id) }
                        }
                    )
                } else {
                    fleetLandingContent
                }
                if activeRun != nil {
                    bottomBar
                }
            }
            .background(t.bg.ignoresSafeArea())
            if activeRun == nil && !isHistorical {
                Button {
                    Haptics.medium()
                    showComposer = true
                } label: {
                    DSIconView(.plus, size: 20, color: t.accentFg)
                        .frame(width: 58, height: 58)
                        .background(t.accent)
                        .clipShape(Circle())
                        .shadow(color: t.accent.opacity(0.28), radius: 18, y: 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New chat")
                .padding(.trailing, 22)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            if selectedAgentID.isEmpty, let first = agents.first(where: { !$0.isOffline }) {
                selectedAgentID = first.id
            }
        }
        .task {
            guard let cid = initialConversationID, turns.isEmpty else { return }
            await loadConversation(id: cid)
        }
        .sheet(isPresented: $showComposer) {
            composerSheet
                .presentationDetents([.height(500), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAgentPicker) {
            agentPickerSheet
        }
        .sheet(isPresented: $showBudgetSheet) {
            BudgetSheet { usd in Task { await controlStore?.setBudget(usd) } }
                .presentationDetents([.height(260)])
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

    // MARK: - Active chat header (post-dispatch)

    private var chatHeader: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.selection()
                resetForNewChat()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(t.text)
                    .frame(width: 42, height: 42)
                    .background(t.surface2, in: Circle())
                    .overlay(Circle().strokeBorder(t.border.opacity(0.8), lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(chatTitle)
                    .font(.dsSansPt(17, weight: .semibold))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                if isStreaming {
                    Text("Agent is working")
                        .font(.dsSansPt(12, weight: .medium))
                        .foregroundStyle(t.text3)
                }
            }
            Spacer()
            Button {
                Haptics.selection()
                onOpenWorkspace(selectedAgent)
            } label: {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(t.text2)
                    .frame(width: 42, height: 42)
                    .background(t.surface2, in: Circle())
                    .overlay(Circle().strokeBorder(t.border.opacity(0.8), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open workspace")
            if isStreaming {
                HStack(spacing: 5) {
                    Circle().fill(t.ok).frame(width: 6, height: 6)
                    Text("working")
                        .font(.dsSansPt(12, weight: .semibold))
                        .foregroundStyle(t.ok)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(t.okSoft, in: Capsule())
            } else {
                Button {
                    Haptics.selection()
                    resetForNewChat()
                } label: {
                    DSIconView(.plus, size: 16, color: t.text2)
                        .frame(width: 42, height: 42)
                        .background(t.surface2, in: Circle())
                        .overlay(Circle().strokeBorder(t.border.opacity(0.8), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New chat")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(t.bg.opacity(0.96))
    }

    // MARK: - Fleet landing content (pre-dispatch)

    private var fleetLandingContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if agents.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    DSIconView(.server, size: 32, color: t.text4)
                    Text("No agents connected")
                        .font(.dsSansPt(17, weight: .semibold))
                        .foregroundStyle(t.text4)
                    Text("Pair a host in Settings to start dispatching work.")
                        .font(.dsSansPt(14))
                        .foregroundStyle(t.text4)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
            } else {
                Text("AGENTS")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text4)
                    .tracking(2)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                VStack(spacing: 0) {
                    ForEach(agents) { agent in
                        Button {
                            selectedAgentID = agent.id
                            showComposer = true
                        } label: {
                            HStack(spacing: 12) {
                                DSIconView(.server, size: 16, color: agent.isOffline ? t.text4 : t.text2)
                                    .frame(width: 34, height: 34)
                                    .background(t.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.name)
                                        .font(.dsSansPt(15, weight: .semibold))
                                        .foregroundStyle(agent.isOffline ? t.text4 : t.text)
                                        .lineLimit(1)
                                    Text(agent.cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                        .font(.dsMonoPt(10))
                                        .foregroundStyle(t.text4)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Circle()
                                    .fill(agent.isOffline ? t.text4 : t.ok)
                                    .frame(width: 7, height: 7)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        if agent.id != agents.last?.id {
                            Rectangle().fill(t.border).frame(height: 0.5).padding(.leading, 20)
                        }
                    }
                }
                .background(t.surface, in: RoundedRectangle(cornerRadius: t.r4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                        .strokeBorder(t.border.opacity(0.7), lineWidth: 1)
                )
                .padding(.horizontal, 20)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Composer bottom sheet

    private var composerSheet: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("New chat")
                            .font(.dsDisplayPt(27, weight: .bold))
                            .foregroundStyle(t.text)
                        Text("Describe the work. Conduit will route it through policy before anything runs.")
                            .font(.dsSansPt(14))
                            .foregroundStyle(t.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button { showComposer = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(t.text2)
                            .frame(width: 42, height: 42)
                            .background(t.surface2, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close composer")
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $prompt)
                        .font(.dsSansPt(17))
                        .foregroundStyle(t.text)
                        .tint(t.accent)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 118, maxHeight: 170)
                        .padding(14)
                        .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(t.border.opacity(0.72), lineWidth: 1)
                        )
                    if prompt.isEmpty {
                        Text("Describe a task or just say hi...")
                            .font(.dsSansPt(17))
                            .foregroundStyle(t.text4)
                            .padding(.horizontal, 20)
                            .padding(.top, 22)
                            .allowsHitTesting(false)
                    }
                }

                HStack(spacing: 10) {
                    composerPill(
                        title: agentLabel,
                        subtitle: "Agent",
                        icon: .sparkles,
                        tone: selectedAgent?.isOffline == true ? t.text4 : t.accent
                    ) {
                        showComposer = false
                        showAgentPicker = true
                    }
                    composerPill(
                        title: machineLabel,
                        subtitle: "Host",
                        icon: .server,
                        tone: t.text3
                    ) {
                        showComposer = false
                        showAgentPicker = true
                    }
                }

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
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
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .navigationBarHidden(true)
    }

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
        HStack(alignment: .top) {
            Spacer(minLength: 56)
            Text(promptText)
                .font(.dsSansPt(16))
                .foregroundStyle(t.accentFg)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(t.accent, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
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
                if !run.blocks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(run.blocks) { block in
                            InlineChatToolCard(block: block)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !run.text.isEmpty {
                    StreamingOutputText(text: run.text, isStreaming: isLast && isStreaming)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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
        guard let agent = selectedAgent else { return "No host" }
        let name = agent.name
        let dir = agent.cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return "\(name) \u{00B7} \(dir)"
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
        let outcome = await onDispatch(agent.id, agent.cwd, trimmedPrompt, budget, model)
        switch outcome {
        case .started(let run):
            chatTitle = titleFromPrompt(trimmedPrompt)
            sentPrompt = trimmedPrompt
            activeRun = run
            turns = [ChatTurn(prompt: trimmedPrompt, runId: run.runId)]
            controlStore = RunControlStore(channel: run.channel, runId: run.runId)
            prompt = ""
            selectedModel = ""
            budgetText = ""
            // Persist conversation + turn
            if let chatRepo {
                Task {
                    let conv = try? await chatRepo.createConversation(
                        title: chatTitle, agentID: agent.vendor.isEmpty ? agent.name : agent.vendor,
                        hostName: agent.name, hostID: agent.hostID, cwd: agent.cwd
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
        sentPrompt = ""
        turns = []
        prompt = ""
        followUpText = ""
        dispatchErrorMessage = nil
        conversationID = nil
        isHistorical = false
    }

    private func loadConversation(id cid: String) async {
        guard let repo = chatRepo else { return }
        guard let conv = try? await repo.conversation(id: cid) else { return }
        let persisted = (try? await repo.turns(conversationID: cid)) ?? []
        await MainActor.run {
            chatTitle = conv.title
            conversationID = cid
            turns = []
            for p in persisted {
                runOutputStore.register(runId: p.runID, status: "exited")
                runOutputStore.appendOutput(RunOutputParams(runId: p.runID, stream: "stdout", chunk: p.assistantText, seq: 0))
            }
            turns = persisted.map { ChatTurn(prompt: $0.prompt, runId: $0.runID) }
            isHistorical = true
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

    private var agentPickerSheet: some View {
        NavigationStack {
            ZStack {
                t.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(groupedAgents, id: \.0) { group in
                            agentPickerGroup(machine: group.0, agents: group.1)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Choose agent")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationBackground(t.bg)
        .presentationDetents([.medium, .large])
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

private struct InlineChatToolCard: View {
    let block: RunOutputStore.ToolBlock
    @Environment(\.conduitTokens) private var t

    private var command: String {
        guard let data = block.inputJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return block.toolName }
        if let cmd = json["command"] as? String { return cmd }
        if let path = json["path"] as? String { return path }
        return block.toolName
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(block.status == .running ? t.info : t.ok)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(block.toolName.uppercased())
                        .font(.dsMonoPt(9, weight: .semibold))
                        .foregroundStyle(t.text4)
                        .tracking(0.8)
                    Spacer()
                    if block.status == .running {
                        PixelBox(state: .streaming, size: 7, subdivisions: 2)
                    } else {
                        DSStatusDot(tone: .ok, size: 6)
                    }
                }
                Text(command)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: t.r2, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                .strokeBorder(t.border.opacity(0.65), lineWidth: 1)
        )
    }
}
#endif
