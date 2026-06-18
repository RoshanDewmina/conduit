#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit

// MARK: - DispatchAgent

public struct DispatchAgent: Identifiable {
    public let id: String
    public let name: String
    public let cwd: String
    public let isOffline: Bool

    /// The agent kind after the "|" separator in id, e.g. "opencode", "claudeCode", "codex".
    public var vendor: String {
        id.split(separator: "|", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
    }

    public init(id: String, name: String, cwd: String, isOffline: Bool) {
        self.id = id
        self.name = name
        self.cwd = cwd
        self.isOffline = isOffline
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
    let onDispatch: (_ agentID: String, _ cwd: String, _ prompt: String, _ budgetUSD: Double?, _ model: String?) async -> ChatDispatchOutcome
    let onNewTask: () -> Void

    @State private var prompt: String = ""
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

    @Environment(\.conduitTokens) private var t

    public init(
        agents: [DispatchAgent],
        runOutputStore: RunOutputStore,
        onDispatch: @escaping (_ agentID: String, _ cwd: String, _ prompt: String, _ budgetUSD: Double?, _ model: String?) async -> ChatDispatchOutcome,
        onNewTask: @escaping () -> Void
    ) {
        self.agents = agents
        self.runOutputStore = runOutputStore
        self.onDispatch = onDispatch
        self.onNewTask = onNewTask
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
            header

            if activeRun != nil {
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
            } else {
                ZStack(alignment: .topLeading) {
                    t.bg.ignoresSafeArea()
                    TextEditor(text: $prompt)
                        .font(.dsSansPt(16))
                        .foregroundStyle(t.text)
                        .tint(t.accent)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                    if prompt.isEmpty {
                        Text("Describe a task or just say hi\u{2026}")
                            .font(.dsSansPt(16))
                            .foregroundStyle(t.text4)
                            .padding(.horizontal, 22)
                            .padding(.top, 20)
                            .allowsHitTesting(false)
                    }
                }

                if showOptions {
                    optionsPanel
                }
            }

            bottomBar
        }
        .background(t.bg.ignoresSafeArea())
        .onAppear {
            if selectedAgentID.isEmpty, let first = agents.first(where: { !$0.isOffline }) {
                selectedAgentID = first.id
            }
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

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text(chatTitle)
                .font(.dsDisplayPt(32, weight: .bold))
                .foregroundStyle(t.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            if activeRun != nil {
                Button {
                    Haptics.selection()
                    resetForNewChat()
                } label: {
                    DSIconView(.plus, size: 16, color: t.text2)
                        .frame(width: 36, height: 36)
                        .background(t.surface)
                        .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New chat")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
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
                .font(.dsSansPt(15))
                .foregroundStyle(t.text)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(t.surface)
                .overlay(Rectangle().strokeBorder(t.accent.opacity(0.35), lineWidth: 1))
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
                            .font(.dsMonoPt(10))
                            .foregroundStyle(t.text4)
                    }
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
            VStack(spacing: 0) {
                Rectangle().fill(t.border).frame(height: 0.5)
                RunFollowUpBar(
                    text: $followUpText,
                    isErrorState: isErrorState,
                    onSend: { followUp in Task { await sendFollowUp(followUp) } }
                )
                .padding(.horizontal, 18)
                .padding(.top, 8)
                RunControlBar(
                    store: controlStore,
                    isTerminal: runIsTerminal,
                    failed: currentRun?.status == "failed",
                    exitCode: currentRun?.exitCode,
                    onStop: { confirmStop = true },
                    onShowBudget: { showBudgetSheet = true }
                )
                .padding(.top, 8)
            }
            .background(t.bg.ignoresSafeArea(edges: .bottom))
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
            Rectangle().fill(t.border).frame(height: 0.5)
            HStack(spacing: 8) {
                // Agent chip
                Button { showAgentPicker = true } label: {
                    HStack(spacing: 5) {
                        DSStatusDot(tone: .accent, size: 7)
                        Text(agentLabel)
                            .font(.dsMonoPt(12, weight: .semibold))
                            .foregroundStyle(t.text)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(t.surface)
                    .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                // Machine \u{00B7} dir chip
                Button { showAgentPicker = true } label: {
                    Text(machineLabel)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(t.surface)
                        .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()

                // Options toggle
                Button { withAnimation { showOptions.toggle() } } label: {
                    Text("Options")
                        .font(.dsMonoPt(12))
                        .foregroundStyle(showOptions ? t.text : t.text3)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(showOptions ? t.surface : t.bg)
                        .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                // Send
                Button {
                    Task { await sendCurrentPrompt() }
                } label: {
                    DSIconView(.send, size: 16, color: canSend ? t.text : t.text4)
                        .frame(width: 36, height: 36)
                        .background(canSend ? t.surface : t.bg)
                        .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
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
        chatTitle = "new chat"
        sentPrompt = ""
        turns = []
        prompt = ""
        followUpText = ""
        dispatchErrorMessage = nil
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
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(t.border).frame(height: 0.5)
            VStack(alignment: .leading, spacing: 8) {
                Text("MODEL")
                    .font(.dsMonoPt(10, weight: .medium))
                    .foregroundStyle(t.text3)
                    .tracking(1.0)
                Menu {
                    Button("Auto (agent default)") { selectedModel = "" }
                    if selectedAgent?.vendor == "claudeCode" {
                        Button("Claude Sonnet 4") { selectedModel = "claude-sonnet-4" }
                        Button("Claude Haiku 4") { selectedModel = "claude-haiku-4" }
                    }
                    if selectedAgent?.vendor == "opencode" {
                        Button("DeepSeek V4 Flash (free)") { selectedModel = "opencode/deepseek-v4-flash-free" }
                        Button("MiMo V2.5 (free)") { selectedModel = "opencode/mimo-v2.5-free" }
                    }
                } label: {
                    HStack {
                        Text(selectedModel.isEmpty ? "Auto (agent default)" : selectedModel)
                            .font(.dsMonoPt(13))
                            .foregroundStyle(t.text)
                        Spacer()
                        DSIconView(.chevronDown, size: 12, color: t.text3)
                    }
                    .padding(10)
                    .background(t.surfaceSunk)
                    .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("BUDGET CAP")
                    .font(.dsMonoPt(10, weight: .medium))
                    .foregroundStyle(t.text3)
                    .tracking(1.0)
                HStack(spacing: 6) {
                    Text("$").font(.dsMonoPt(13)).foregroundStyle(t.text3)
                    TextField("None", text: $budgetText)
                        .font(.dsMonoPt(13))
                        .foregroundStyle(t.text)
                        .keyboardType(.decimalPad)
                }
                .padding(10)
                .background(t.surfaceSunk)
                .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(t.surface)
    }

    private var agentPickerSheet: some View {
        NavigationStack {
            ZStack {
                t.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(agents) { agent in
                            let isSelected = agent.id == selectedAgentID
                            Button {
                                guard !agent.isOffline else { return }
                                selectedAgentID = agent.id
                                showAgentPicker = false
                            } label: {
                                HStack(spacing: 12) {
                                    DSStatusDot(tone: agent.isOffline ? .off : .ok, size: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(agent.name)
                                            .font(.dsMonoPt(14, weight: .semibold))
                                            .foregroundStyle(agent.isOffline ? t.text4 : t.text)
                                        Text(agent.vendor.isEmpty ? agent.cwd : "\(agent.vendor) \u{00B7} \(agent.cwd)")
                                            .font(.dsMonoPt(11))
                                            .foregroundStyle(t.text3)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if isSelected {
                                        DSIconView(.check, size: 14, color: t.accent)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(agent.isOffline)
                            Rectangle().fill(t.border).frame(height: 0.5).padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Choose agent")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
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
                .fill(block.status == .running ? t.accent : t.ok)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
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
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(t.surfaceSunk)
        .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
    }
}
#endif
