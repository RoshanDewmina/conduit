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

    open func decide(_ id: ApprovalID, decision: Approval.Decision) {
        if let idx = approvals.firstIndex(where: { $0.id == id }) {
            approvals[idx].decision = decision
            approvals[idx].decidedAt = .now
            Haptics.selection()
        }
    }
}

public struct InboxView: View {
    private var vm: InboxViewModel
    private let sessionID: SessionID?
    private let title: String

    @Environment(\.conduitTokens) private var t

    public init(viewModel: InboxViewModel, sessionID: SessionID? = nil, title: String = "Inbox") {
        self.vm = viewModel
        self.sessionID = sessionID
        self.title = title
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Title row
                HStack(alignment: .center) {
                    Text(title)
                        .font(.dsDisplayPt(30, weight: .bold))
                        .foregroundStyle(t.text)
                    if pendingCount > 0 {
                        Text("\(pendingCount)")
                            .font(.dsMonoPt(12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(t.accent)
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

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
                        .padding(.top, 4)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
    }

    // MARK: - Decided row (compact)

    @ViewBuilder
    private func decidedRow(_ approval: Approval) -> some View {
        HStack(spacing: 12) {
            AgentIdentityBadge(agent: agentKey(approval.agent), label: nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(approval.command ?? actionPhrase(approval.kind))
                    .font(.dsMonoPt(13))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                Text(approval.cwd)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .lineLimit(1)
            }
            Spacer()
            if let d = approval.decision {
                let approved = d == .approved || d == .approvedAlways
                DSChip(d == .approvedAlways ? "always" : d.rawValue, tone: approved ? .ok : .danger, style: .soft)
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
                icon: .inbox,
                title: "Inbox is empty",
                subtitle: "Agent approvals and run results appear here.",
                action: nil
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
        case .command:    "run a command"
        case .patch:      "apply a patch"
        case .fileWrite:  "write a file"
        case .fileDelete: "delete a file"
        case .network:    "make a network call"
        case .credential: "access a credential"
        case .browser:    "perform a browser action"
        }
    }
}

#endif
