#if os(iOS)
import SwiftUI
import DesignSystem
import SessionFeature

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

// MARK: - DispatchView

public struct DispatchView: View {
    let agents: [DispatchAgent]
    let onDispatch: (_ agentID: String, _ cwd: String, _ prompt: String, _ budgetUSD: Double?, _ model: String?) -> Void

    @State private var selectedAgentID: String?
    @State private var cwd: String = ""
    @State private var prompt: String = ""
    @State private var budgetText: String = ""
    @State private var selectedModel: String = ""
    @State private var dictationEngine: DictationEngine?
    @State private var isDictating = false

    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss

    private var modelOptions: [(label: String, slug: String)] {
        switch selectedAgent?.vendor ?? "" {
        case "claudeCode":
            [
                ("Agent default", ""),
                ("Claude Sonnet 4", "claude-sonnet-4"),
                ("Claude Haiku 4", "claude-haiku-4"),
            ]
        case "opencode":
            [
                ("Agent default", ""),
                ("DeepSeek V4 Flash (free)", "opencode/deepseek-v4-flash-free"),
                ("MiMo V2.5 (free)", "opencode/mimo-v2.5-free"),
                ("North Mini Code (free)", "opencode/north-mini-code-free"),
            ]
        default:
            [("Agent default", "")]
        }
    }

    public init(
        agents: [DispatchAgent],
        onDispatch: @escaping (_ agentID: String, _ cwd: String, _ prompt: String, _ budgetUSD: Double?, _ model: String?) -> Void
    ) {
        self.agents = agents
        self.onDispatch = onDispatch
    }

    // MARK: - Derived

    private var selectedAgent: DispatchAgent? {
        agents.first { $0.id == selectedAgentID }
    }

    private var canDispatch: Bool {
        guard let agent = selectedAgent, !agent.isOffline else { return false }
        return !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var parsedBudget: Double? {
        let trimmed = budgetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    // MARK: - Body

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader("dispatch", onBack: { dismiss() })
                breadcrumbRow
                scrollContent
                footerCTA
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            if selectedAgentID == nil, let first = agents.first(where: { !$0.isOffline }) {
                selectedAgentID = first.id
                cwd = first.cwd
            }
        }
        .onChange(of: selectedAgentID) { _, _ in
            selectedModel = ""
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumbRow: some View {
        HStack(spacing: 6) {
            Text("~/conduit").foregroundStyle(t.text4)
            Text("›").foregroundStyle(t.accent)
            Text("start a task").foregroundStyle(t.text3)
            Spacer()
        }
        .font(.dsMonoPt(11))
        .lineLimit(1)
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                agentPickerSection
                modelSection
                cwdSection
                promptSection
                budgetSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Agent picker

    private var agentPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSListSectionHead("Agent")
            VStack(spacing: 0) {
                ForEach(agents) { agent in
                    agentRow(agent)
                    if agent.id != agents.last?.id {
                        DSDivider()
                    }
                }
            }
            .background(t.surface)
            .overlay(
                RoundedRectangle(cornerRadius: t.r1, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func agentRow(_ agent: DispatchAgent) -> some View {
        let isSelected = selectedAgentID == agent.id
        Button {
            guard !agent.isOffline else { return }
            Haptics.selection()
            selectedAgentID = agent.id
            cwd = agent.cwd
        } label: {
            HStack(spacing: 12) {
                DSStatusDot(tone: agent.isOffline ? .off : .ok, size: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.dsMonoPt(13, weight: .semibold))
                        .foregroundStyle(agent.isOffline ? t.text4 : t.text)
                    Text(agent.cwd)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(agent.isOffline ? t.text4 : t.text3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if agent.isOffline {
                    DSChip("offline", tone: .neutral, variant: .outlined, size: .sm)
                } else if isSelected {
                    DSChip("selected", tone: .accent, variant: .soft, size: .sm)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(agent.isOffline)
    }

    // MARK: - Working directory

    private var cwdSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSListSectionHead("Working directory")
            TextField("~/path/to/project", text: $cwd)
                .font(.dsMonoPt(13))
                .foregroundStyle(t.text)
                .tint(t.accent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(12)
                .background(t.surfaceSunk)
                .overlay(
                    RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1)
                )
        }
    }

    // MARK: - Task prompt

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSListSectionHead("Task")
            TextEditor(text: $prompt)
                .font(.dsSansPt(14))
                .foregroundStyle(t.text)
                .tint(t.accent)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(12)
                .background(t.surfaceSunk)
                .overlay(
                    RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if prompt.isEmpty {
                        Text("Describe the task…")
                            .font(.dsSansPt(14))
                            .foregroundStyle(t.text4)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        if isDictating {
                            dictationEngine?.stop()
                            dictationEngine = nil
                            isDictating = false
                        } else {
                            let engine = DictationEngine()
                            dictationEngine = engine
                            isDictating = true
                            Task {
                                await engine.start { text in
                                    prompt = text
                                }
                            }
                        }
                    } label: {
                        Image(systemName: isDictating ? "mic.fill" : "mic")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isDictating ? t.accent : t.text3)
                            .frame(width: 30, height: 30)
                            .background(t.surfaceSunk)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(t.border, lineWidth: 1)
                            )
                            .phaseAnimator([0, 1], trigger: isDictating) { content, phase in
                                content
                                    .scaleEffect(isDictating ? 1 + CGFloat(phase) * 0.12 : 1)
                            } animation: { _ in
                                .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
        }
    }

    // MARK: - Model

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSListSectionHead("Model")
            Menu {
                ForEach(modelOptions, id: \.slug) { option in
                    Button(option.label) { selectedModel = option.slug }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(modelOptions.first { $0.slug == selectedModel }?.label ?? "Agent default")
                        .font(.dsMonoPt(14))
                        .foregroundStyle(t.text)
                    Spacer()
                    DSIconView(.chevronDown, size: 13, color: t.text3)
                }
                .padding(12)
                .background(t.surfaceSunk)
                .overlay(
                    RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1)
                )
            }
            Text("Overrides the agent's configured model for this run.")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text4)
        }
    }

    // MARK: - Budget

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSListSectionHead("Daily budget (optional)")
            HStack(spacing: 8) {
                Text("$")
                    .font(.dsMonoPt(14, weight: .semibold))
                    .foregroundStyle(t.text3)
                TextField("0.00", text: $budgetText)
                    .font(.dsMonoPt(14))
                    .foregroundStyle(t.text)
                    .tint(t.accent)
                    .keyboardType(.decimalPad)
                    .autocorrectionDisabled()
            }
            .padding(12)
            .background(t.surfaceSunk)
            .overlay(
                RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
            Text("Leave blank for no cap.")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text4)
        }
    }

    // MARK: - Footer CTA

    private var footerCTA: some View {
        VStack(spacing: 0) {
            Rectangle().fill(t.border).frame(height: 1)
            VStack(spacing: 0) {
                DSButton("Dispatch task", variant: .primary, size: .md, mono: true, fullWidth: true) {
                    guard let agent = selectedAgent else { return }
                    Haptics.success()
                    onDispatch(
                        agent.id,
                        cwd.trimmingCharacters(in: .whitespacesAndNewlines),
                        prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                        parsedBudget,
                        selectedModel.isEmpty ? nil : selectedModel
                    )
                }
                .disabled(!canDispatch)
                .frame(height: 52)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .padding(.bottom, 8)
        }
        .background(t.bg)
    }
}

// MARK: - Preview

#Preview("Dispatch — dark") {
    DispatchView(
        agents: [
            DispatchAgent(id: "a1", name: "dev-box", cwd: "~/code/command-center", isOffline: false),
            DispatchAgent(id: "a2", name: "ci-runner", cwd: "~/ci", isOffline: false),
            DispatchAgent(id: "a3", name: "staging-01", cwd: "~/deploy", isOffline: true),
        ],
        onDispatch: { agentID, cwd, prompt, budget, model in
            print("dispatch → \(agentID) cwd=\(cwd) budget=\(budget.map { "$\($0)" } ?? "nil") model=\(model ?? "default")")
        }
    )
    .environment(\.conduitTokens, .dark)
    .preferredColorScheme(.dark)
}
#endif
