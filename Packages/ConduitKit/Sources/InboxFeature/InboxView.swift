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
    @State private var vm: InboxViewModel
    private let sessionID: SessionID?
    private let title: String

    public init(viewModel: InboxViewModel, sessionID: SessionID? = nil, title: String = "Inbox") {
        _vm = State(initialValue: viewModel)
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
                    .listRowInsets(.init(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
            }
        }
        .listStyle(.plain)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                riskBadge
                Text(approval.agent.rawValue.capitalized)
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(approval.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if let cmd = approval.command {
                Text(cmd)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Text("cwd: \(approval.cwd)").font(.caption.monospaced()).foregroundStyle(.tertiary)

            if approval.isPending {
                ViewThatFits(in: .horizontal) {
                    decisionButtons(axis: .horizontal)
                    decisionButtons(axis: .vertical)
                }
            } else if let d = approval.decision {
                Label(d.rawValue.capitalized, systemImage: d == .approved ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.caption).foregroundStyle(d == .approved ? .green : .red)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func decisionButtons(axis: Axis) -> some View {
        let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        layout {
            Button {
                onDecide(.approved)
            } label: {
                Label("Allow once", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) {
                onDecide(.rejected)
            } label: {
                Label("Reject", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
        }
    }

    private var riskBadge: some View {
        let label: String = switch approval.risk {
        case .low: "low risk"
        case .medium: "medium risk"
        case .high: "HIGH RISK"
        case .critical: "CRITICAL"
        }
        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(RiskTint.color(for: approval.risk.rawValue).opacity(0.2)))
            .foregroundStyle(RiskTint.color(for: approval.risk.rawValue))
    }
}

#endif
