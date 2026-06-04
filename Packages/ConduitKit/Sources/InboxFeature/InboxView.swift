#if os(iOS)
import SwiftUI
import Observation
import ConduitCore
import AgentKit
import DesignSystem
import DiffKit
import DiffFeature

@MainActor @Observable
public class InboxViewModel {
    public var approvals: [Approval] = []

    public init(approvals: [Approval] = []) {
        self.approvals = approvals
    }

    open func decide(
        _ id: ApprovalID,
        decision: Approval.Decision,
        choiceIndex: Int? = nil,
        editedToolInput: String? = nil
    ) {
        if let idx = approvals.firstIndex(where: { $0.id == id }) {
            approvals[idx].decision = decision
            approvals[idx].decidedAt = .now
            if let ci = choiceIndex { approvals[idx].answeredChoice = ci }
            if let edited = editedToolInput, !edited.isEmpty {
                approvals[idx].toolInput = edited
            }
            Haptics.selection()
        }
    }
}

public struct InboxView: View {
    private var vm: InboxViewModel
    private let sessionID: SessionID?
    private let title: String
    private let awayAuditEntries: [AuditLogEntry]
    public var statusHeaderAgents: [AgentInfo] = []
    public var onTapStatusHeader: () -> Void = {}

    @Environment(\.conduitTokens) private var t
    @State private var editingApproval: Approval?
    @State private var editedToolInputText = ""
    @State private var diffApproval: Approval?

    public init(
        viewModel: InboxViewModel,
        sessionID: SessionID? = nil,
        title: String = "Inbox",
        awayAuditEntries: [AuditLogEntry] = [],
        statusHeaderAgents: [AgentInfo] = [],
        onTapStatusHeader: @escaping () -> Void = {}
    ) {
        self.vm = viewModel
        self.sessionID = sessionID
        self.title = title
        self.awayAuditEntries = awayAuditEntries
        self.statusHeaderAgents = statusHeaderAgents
        self.onTapStatusHeader = onTapStatusHeader
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── BLOCKS header
                DSScreenHeader(
                    "inbox",
                    breadcrumb: "agent approvals",
                    count: pendingCount > 0 ? "\(pendingCount) pending" : nil
                )

                if !statusHeaderAgents.isEmpty {
                    AgentStatusHeader(agents: statusHeaderAgents, onTap: onTapStatusHeader)
                }

                Spacer().frame(height: 12)

                if !awayAuditEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        DSListSectionHead("WHILE YOU WERE AWAY", count: awayAuditEntries.count)
                        BridgeAuditFeedView(entries: awayAuditEntries)
                            .padding(.horizontal, 16)
                    }
                }

                if visibleApprovals.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            let pending = visibleApprovals.filter { $0.isPending }
                            let decided = visibleApprovals.filter { !$0.isPending }

                            if !pending.isEmpty {
                                DSListSectionHead("PENDING", count: pending.count)
                                ForEach(pending) { approval in
                                    pendingCard(approval)
                                        .padding(.horizontal, 16)
                                }
                            }

                            if !decided.isEmpty {
                                DSListSectionHead("DECIDED", count: decided.count)
                                ForEach(decided) { approval in
                                    decidedRow(approval)
                                }
                            }
                        }
                        // BUG-4: constrain scroll content to the viewport width so wide
                        // rows at large Dynamic Type wrap instead of overflowing and being
                        // centre-clipped on the leading edge by the ScrollView.
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .sheet(item: $editingApproval) { approval in
            editSheet(approval)
        }
        .sheet(item: $diffApproval) { approval in
            diffSheet(approval)
        }
    }

    // MARK: - Pending card dispatch

    @ViewBuilder
    private func pendingCard(_ approval: Approval) -> some View {
        switch approval.kind {
        case .askQuestion:
            DSAskQuestionCard(
                agentKey: agentKey(approval.agent),
                agentName: agentName(approval.agent),
                hostLabel: approval.cwd,
                timeLabel: approval.createdAt.formatted(date: .omitted, time: .shortened),
                question: approval.question ?? "What should I do next?",
                choices: approval.choices ?? [],
                onAnswer: { idx in
                    vm.decide(approval.id, decision: .approved, choiceIndex: idx)
                }
            )

        case .callMCP:
            DSMCPCallCard(
                agentKey: agentKey(approval.agent),
                agentName: agentName(approval.agent),
                hostLabel: approval.cwd,
                timeLabel: approval.createdAt.formatted(date: .omitted, time: .shortened),
                toolName: approval.toolName ?? approval.command ?? "unknown_tool",
                toolUseID: approval.toolUseID,
                args: summarizedToolInput(approval),
                risk: approval.risk.rawValue,
                onDeny: { vm.decide(approval.id, decision: .rejected) },
                onEditAndRun: {
                    editedToolInputText = editableToolInput(for: approval)
                    editingApproval = approval
                },
                onAllowAlways: { vm.decide(approval.id, decision: .approvedAlways) },
                onApprove: { vm.decide(approval.id, decision: .approved) }
            )

        default:
            VStack(alignment: .leading, spacing: 8) {
                DSApprovalCard(
                    agentKey: agentKey(approval.agent),
                    risk: approval.risk.rawValue,
                    timeLabel: approval.createdAt.formatted(date: .omitted, time: .shortened),
                    agentName: agentName(approval.agent),
                    action: actionPhrase(approval.kind),
                    hostLabel: approval.cwd,
                    command: approval.command,
                    onViewDiff: approval.patch != nil ? { diffApproval = approval } : nil,
                    onDeny: { vm.decide(approval.id, decision: .rejected) },
                    onAllowAlways: { vm.decide(approval.id, decision: .approvedAlways) },
                    onEditAndRun: (approval.toolInput != nil || approval.command != nil) ? {
                        editedToolInputText = editableToolInput(for: approval)
                        editingApproval = approval
                    } : nil,
                    onApprove: { vm.decide(approval.id, decision: .approved) }
                )
                if let br = approval.blastRadius {
                    DSBlastRadiusBanner(blastRadius: br)
                }
            }
        }
    }

    @ViewBuilder
    private func editSheet(_ approval: Approval) -> some View {
        let original = editableToolInput(for: approval)
        let payload = editedToolInputJSON(for: approval, editedText: editedToolInputText)
        let preview = toolInputDiff(original: original, edited: payload)
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit tool input JSON before running")
                    .font(.dsSansPt(14))
                    .foregroundStyle(t.text2)
                TextEditor(text: $editedToolInputText)
                    .font(.dsMonoPt(13))
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(t.surface)
                    .clipShape(RoundedRectangle(cornerRadius: t.r3))

                if let preview {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Proposed diff")
                            .font(.dsSansPt(13, weight: .medium))
                            .foregroundStyle(t.text2)
                        DiffView(diff: preview)
                            .frame(minHeight: 160)
                            .clipShape(RoundedRectangle(cornerRadius: t.r3))
                    }
                } else {
                    Text("No changes yet")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                }
            }
            .padding(16)
            .background(t.bg)
            .navigationTitle("Edit & run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingApproval = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Run") {
                        vm.decide(approval.id, decision: .approved, editedToolInput: payload)
                        editingApproval = nil
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func diffSheet(_ approval: Approval) -> some View {
        NavigationStack {
            if let patch = approval.patch {
                DiffView(diff: UnifiedDiffParser.parse(patch))
                    .navigationTitle("Patch Diff")
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("No diff available", systemImage: "plusminus")
            }
        }
    }

    private func editableToolInput(for approval: Approval) -> String {
        guard let toolInput = approval.toolInput, !toolInput.isEmpty else {
            let command = approval.command ?? ""
            if let data = try? JSONSerialization.data(withJSONObject: ["command": command], options: [.prettyPrinted]),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return command
        }
        guard
            let data = toolInput.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
            let pretty = String(data: prettyData, encoding: .utf8)
        else {
            return toolInput
        }
        return pretty
    }

    private func summarizedToolInput(_ approval: Approval) -> String? {
        guard let toolInput = approval.toolInput, !toolInput.isEmpty else {
            return approval.patch ?? approval.command
        }
        return toolInput.count > 240 ? String(toolInput.prefix(240)) + "…" : toolInput
    }

    private func editedToolInputJSON(for approval: Approval, editedText: String) -> String {
        let trimmed = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return editedText }
        if let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return trimmed
        }
        if let existing = approval.toolInput,
           let existingData = existing.data(using: .utf8),
           var object = (try? JSONSerialization.jsonObject(with: existingData)) as? [String: Any] {
            object["command"] = trimmed
            if let out = try? JSONSerialization.data(withJSONObject: object),
               let str = String(data: out, encoding: .utf8) {
                return str
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: ["command": trimmed]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return editedText
    }

    private func toolInputDiff(original: String, edited: String) -> UnifiedDiff? {
        guard original != edited else { return nil }
        let oldLines = original.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = edited.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let oldCount = max(oldLines.count, 1)
        let newCount = max(newLines.count, 1)
        var lines: [String] = [
            "--- a/tool_input.json",
            "+++ b/tool_input.json",
            "@@ -1,\(oldCount) +1,\(newCount) @@",
        ]
        lines.append(contentsOf: oldLines.map { "-\($0)" })
        lines.append(contentsOf: newLines.map { "+\($0)" })
        return UnifiedDiffParser.parse(lines.joined(separator: "\n"))
    }

    // MARK: - Decided row (compact)

    @ViewBuilder
    private func decidedRow(_ approval: Approval) -> some View {
        HStack(spacing: 12) {
            AgentIdentityBadge(agent: agentKey(approval.agent), label: nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(decidedLabel(approval))
                    .font(.dsMonoPt(13))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                Text(approval.cwd)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            if let d = approval.decision {
                let approved = d == .approved || d == .approvedAlways
                if d == .approved, let ci = approval.answeredChoice,
                   let choices = approval.choices, ci < choices.count {
                    DSChip("→ \(choices[ci])", tone: .ok, style: .soft)
                } else {
                    DSChip(d == .approvedAlways ? "always" : d.rawValue, tone: approved ? .ok : .danger, style: .soft)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack {
            Spacer()
            DSEmptyState(
                dotMatrix: .idle,
                title: "inbox zero",
                subtitle: "Nothing waiting on you. Agents are running clean."
            )
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    // MARK: - Computed

    private var visibleApprovals: [Approval] {
        guard let sessionID else { return vm.approvals }
        return vm.approvals.filter { $0.sessionID == sessionID }
    }

    private var pendingCount: Int {
        visibleApprovals.filter { $0.isPending }.count
    }

    // MARK: - Mapping helpers

    private func agentKey(_ source: Approval.AgentSource) -> AgentKey {
        switch source {
        case .claudeCode: return .claudeCode
        case .codex:      return .codex
        case .cursor:     return .cursor
        case .opencode:   return .opencode
        case .devin:      return .devin
        case .unknown:    return .unknown
        }
    }

    private func agentName(_ source: Approval.AgentSource) -> String {
        switch source {
        case .claudeCode: "Claude Code"
        case .codex:      "Codex"
        case .cursor:     "Cursor"
        case .opencode:   "OpenCode"
        case .devin:      "Devin"
        case .unknown:    "Agent"
        }
    }

    private func actionPhrase(_ kind: Approval.Kind) -> String {
        switch kind {
        case .command:      "run a command"
        case .patch:        "apply a patch"
        case .fileWrite:    "write a file"
        case .fileDelete:   "delete a file"
        case .network:      "make a network call"
        case .credential:   "access a credential"
        case .browser:      "perform a browser action"
        case .callMCP:      "call an MCP tool"
        case .askQuestion:  "ask a question"
        }
    }

    private func decidedLabel(_ approval: Approval) -> String {
        if approval.kind == .askQuestion,
           let ci = approval.answeredChoice,
           let choices = approval.choices, ci < choices.count {
            return "Answered: \(choices[ci])"
        }
        return approval.command ?? actionPhrase(approval.kind)
    }
}

#endif
