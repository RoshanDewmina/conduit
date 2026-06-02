#if os(iOS)
import SwiftUI
import Observation
import ConduitCore
import AgentKit
import DesignSystem

@MainActor @Observable
public class InboxViewModel {
    public var approvals: [Approval] = []

    public init(approvals: [Approval] = []) {
        self.approvals = approvals
    }

    open func decide(_ id: ApprovalID, decision: Approval.Decision, choiceIndex: Int? = nil) {
        if let idx = approvals.firstIndex(where: { $0.id == id }) {
            approvals[idx].decision = decision
            approvals[idx].decidedAt = .now
            if let ci = choiceIndex { approvals[idx].answeredChoice = ci }
            Haptics.selection()
        }
    }
}

public struct InboxView: View {
    private var vm: InboxViewModel
    private let sessionID: SessionID?
    private let title: String
    public var statusHeaderAgents: [AgentInfo] = []
    public var onTapStatusHeader: () -> Void = {}

    @AppStorage("inbox.autonomyPreset") private var autonomyPresetRaw: String = AutonomyPreset.alwaysAsk.rawValue
    @AppStorage("flag.autonomyPresets") private var autonomyPresetsEnabled: Bool = true

    @Environment(\.conduitTokens) private var t

    private var autonomyPreset: Binding<AutonomyPreset> {
        Binding(
            get: { AutonomyPreset(rawValue: autonomyPresetRaw) ?? .alwaysAsk },
            set: { autonomyPresetRaw = $0.rawValue }
        )
    }

    public init(
        viewModel: InboxViewModel,
        sessionID: SessionID? = nil,
        title: String = "Inbox",
        statusHeaderAgents: [AgentInfo] = [],
        onTapStatusHeader: @escaping () -> Void = {}
    ) {
        self.vm = viewModel
        self.sessionID = sessionID
        self.title = title
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

                if autonomyPresetsEnabled {
                    DSAutonomyPresetBar(preset: autonomyPreset)
                        .padding(.top, 8)
                }

                Spacer().frame(height: 12)

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
                toolName: approval.command ?? "unknown_tool",
                args: approval.patch,
                risk: approval.risk.rawValue,
                onDeny: { vm.decide(approval.id, decision: .rejected) },
                onApprove: { vm.decide(approval.id, decision: .approved) }
            )

        default:
            DSApprovalCard(
                agentKey: agentKey(approval.agent),
                risk: approval.risk.rawValue,
                timeLabel: approval.createdAt.formatted(date: .omitted, time: .shortened),
                agentName: agentName(approval.agent),
                action: actionPhrase(approval.kind),
                hostLabel: approval.cwd,
                command: approval.command,
                onViewDiff: approval.patch != nil ? {} : nil,
                onDeny: { vm.decide(approval.id, decision: .rejected) },
                onAllowAlways: { vm.decide(approval.id, decision: .approvedAlways) },
                onApprove: { vm.decide(approval.id, decision: .approved) }
            )
        }
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
