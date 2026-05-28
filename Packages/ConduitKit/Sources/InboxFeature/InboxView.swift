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
    // Using a plain var (not @State) so SwiftUI's @Observable machinery tracks
    // the *current* viewModel instance. @State would pin the initial instance
    // and ignore subsequent replacements (e.g. when liveInboxVM is set after seeding).
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
        List {
            if visibleApprovals.isEmpty {
                ContentUnavailableView(
                    title == "Inbox" ? "Inbox is empty" : "Session inbox is empty",
                    systemImage: "tray",
                    description: Text("Agent approvals and run results land here.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(visibleApprovals) { approval in
                    ApprovalCard(approval: approval) { decision in
                        vm.decide(approval.id, decision: decision)
                    }
                    .listRowBackground(t.surf1)
                    .listRowInsets(.init(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(t.surf0)
        .navigationTitle(title)
        .contentMargins(.bottom, 72, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 72)
        }
    }

    private var visibleApprovals: [Approval] {
        guard let sessionID else { return vm.approvals }
        return vm.approvals.filter { $0.sessionID == sessionID }
    }
}

private struct ApprovalCard: View {
    let approval: Approval
    var onDecide: (Approval.Decision) -> Void

    @Environment(\.conduitTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                agentMark
                Text(agentLabel)
                    .font(.caption.weight(.semibold)).foregroundStyle(t.text2)
                RiskBadge(risk: approval.risk.rawValue)
                Spacer()
                Text(approval.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2.monospaced()).foregroundStyle(t.text4)
            }

            // Descriptive line: "<Agent> wants to <kind> on <cwd>"
            (Text(agentLabel).font(.caption.weight(.semibold)).foregroundStyle(t.text1)
             + Text(" \(kindPhrase)").font(.caption).foregroundStyle(t.text2))
                .fixedSize(horizontal: false, vertical: true)

            if let cmd = approval.command {
                Text(cmd)
                    .font(.system(.callout, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(t.surf2)
                    .clipShape(RoundedRectangle(cornerRadius: t.radiusSM))
                    .foregroundStyle(t.text1)
            }
            HStack(spacing: 4) {
                Image(systemName: "folder").font(.caption2).foregroundStyle(t.text4)
                Text(approval.cwd).font(.caption2.monospaced()).foregroundStyle(t.text4)
            }

            if approval.isPending {
                ViewThatFits(in: .horizontal) {
                    decisionButtons(axis: .horizontal)
                    decisionButtons(axis: .vertical)
                }
            } else if let d = approval.decision {
                HStack(spacing: 4) {
                    let approved = (d == .approved || d == .approvedAlways)
                    Image(systemName: approved ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(approved ? t.ok : t.danger)
                    Text(d.rawValue.capitalized)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(approved ? t.ok : t.danger)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var agentMark: some View {
        Text(agentInitials)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(t.accent)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var agentInitials: String {
        switch approval.agent {
        case .claudeCode: "CC"
        case .codex:      "CX"
        case .cursor:     "CR"
        case .opencode:   "OC"
        case .devin:      "DV"
        case .unknown:    "?"
        }
    }

    private var agentLabel: String {
        switch approval.agent {
        case .claudeCode: "Claude Code"
        case .codex:      "Codex"
        case .cursor:     "Cursor"
        case .opencode:   "OpenCode"
        case .devin:      "Devin"
        case .unknown:    "Agent"
        }
    }

    private var kindPhrase: String {
        switch approval.kind {
        case .command:    "wants to run a command"
        case .patch:      "wants to apply a patch"
        case .fileWrite:  "wants to write a file"
        case .fileDelete: "wants to delete a file"
        case .network:    "wants to make a network call"
        case .credential: "wants a credential"
        case .browser:    "wants to perform a browser action"
        }
    }

    @ViewBuilder
    private func decisionButtons(axis: Axis) -> some View {
        let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        layout {
            DSButton("Deny", variant: .destructive, size: .sm) { onDecide(.rejected) }
            DSButton("Allow always", variant: .secondary, size: .sm) { onDecide(.approvedAlways) }
            DSButton("Approve", variant: .primary, size: .sm) { onDecide(.approved) }
        }
    }
}

#endif
