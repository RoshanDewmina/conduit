#if os(iOS)
import SwiftUI
import Observation
import ConduitCore
import AgentKit
import DesignSystem
import DiffKit
import DiffFeature
import SecurityKit

@MainActor @Observable
public class InboxViewModel {
    public var approvals: [Approval] = []

    public var effectiveApprovals: [Approval] { approvals }

    /// Optional sink fired after a decision mutates a pending row. The base VM only
    /// mutates local state; the relay/default inbox sets this to forward the decision
    /// to the daemon (LiveInboxViewModel has its own repository-backed onDecision).
    public var decisionSink: ((ApprovalID, Approval.Decision, String?) -> Void)?

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
            if decision == .approvedAlways {
                persistAllowAlwaysRule(for: approvals[idx])
            }
            Haptics.selection()
            decisionSink?(id, decision, editedToolInput)
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
    public var onSetPolicy: ((String) async -> Void)?
    private let onOpenHistory: (() -> Void)?

    @Environment(\.conduitTokens) private var t
    @State private var detailApproval: Approval?
    @State private var editingApproval: Approval?
    @State private var editedToolInputText = ""
    @State private var scopeSheetApproval: Approval?
    /// A deep-linked approval id (notification/Live-Activity body tap) whose row
    /// hasn't loaded yet — on a cold launch `vm.approvals` is empty when the open
    /// signal arrives. Held until the list loads, then resolved in `.onChange`.
    @State private var pendingOpenApprovalID: UUID?

    public init(
        viewModel: InboxViewModel,
        sessionID: SessionID? = nil,
        title: String = "Inbox",
        awayAuditEntries: [AuditLogEntry] = [],
        statusHeaderAgents: [AgentInfo] = [],
        onTapStatusHeader: @escaping () -> Void = {},
        onSetPolicy: ((String) async -> Void)? = nil,
        onOpenHistory: (() -> Void)? = nil
    ) {
        self.vm = viewModel
        self.sessionID = sessionID
        self.title = title
        self.awayAuditEntries = awayAuditEntries
        self.statusHeaderAgents = statusHeaderAgents
        self.onTapStatusHeader = onTapStatusHeader
        self.onSetPolicy = onSetPolicy
        self.onOpenHistory = onOpenHistory
    }

    public var body: some View {
        ConduitPage {
            VStack(spacing: 0) {
                inboxHeader

                if visibleApprovals.filter({ $0.isPending }).isEmpty {
                    inboxHomeDashboard
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            waitingBand
                                .padding(.horizontal, 20)
                                .padding(.bottom, 4)

                            ForEach(Array(pendingGroups.enumerated()), id: \.offset) { _, group in
                                ConduitSectionLabel(group.label)
                                    .padding(.horizontal, 22)
                                    .padding(.top, 6)
                                ForEach(group.approvals) { approval in
                                    pendingCard(approval)
                                        .padding(.horizontal, 20)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 14)
                        .padding(.bottom, 28)
                    }
                }
            }
        }
        .sheet(item: $detailApproval) { approval in
            detailSheet(approval)
        }
        .sheet(item: $editingApproval) { approval in
            editSheet(approval)
        }
        .sheet(item: $scopeSheetApproval) { approval in
            AllowAlwaysScopeSheet(approval: approval) { scopedRule in
                persistScopedAllowAlwaysRule(for: approval, rule: scopedRule)
                let policyYAML = buildPolicyYAML(for: approval, rule: scopedRule)
                Task { await onSetPolicy?(policyYAML) }
                vm.decide(approval.id, decision: .approvedAlways)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .conduitOpenApproval)) { note in
            guard let idString = note.userInfo?["approvalId"] as? String,
                  let uuid = UUID(uuidString: idString) else { return }
            if let match = vm.approvals.first(where: { $0.id.raw == uuid }) {
                detailApproval = match
                pendingOpenApprovalID = nil
            } else {
                // Cold launch: approvals not loaded yet. Remember the id and
                // resolve it once the list arrives (.onChange below). Review
                // intent only — this opens the detail sheet, never decides.
                pendingOpenApprovalID = uuid
            }
        }
        // Resolve a deep-link that arrived before the list loaded. `.count` is a
        // sufficient trigger here (not a strong identity key) because this only
        // matters during the cold-launch window when count goes 0→N; outside it
        // `pendingOpenApprovalID` is nil and the guard short-circuits. The actual
        // match is still an exact id lookup, so it can never open the wrong sheet.
        .onChange(of: vm.approvals.count) { _, _ in
            guard let uuid = pendingOpenApprovalID,
                  let match = vm.approvals.first(where: { $0.id.raw == uuid }) else { return }
            detailApproval = match
            pendingOpenApprovalID = nil
        }
    }

    private var inboxHeader: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(pendingCount > 0 ? (pendingCount == 1 ? "one agent is waiting" : "\(pendingCount) agents are waiting") : "nothing pending")
                    .font(.dsEditorialPt(17))
                    .foregroundStyle(t.accent)
                Text(title)
                    .font(.dsDisplayPt(28, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            if let onOpenHistory {
                Button {
                    Haptics.selection()
                    onOpenHistory()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(t.text3)
                        .frame(width: 44, height: 44)
                        .background(t.surface, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: t.r3, style: .continuous).strokeBorder(t.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("History")
                .accessibilityIdentifier("inboxHistory")
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    // MARK: - Signature "WAITING ON YOU" band

    private var waitingBand: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("WAITING ON YOU")
                .font(.dsMonoPt(10, weight: .medium))
                .tracking(1.0)
                .foregroundStyle(t.accentFg.opacity(0.82))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(pendingCount)")
                    .font(.dsDisplayPt(34, weight: .bold))
                    .foregroundStyle(t.accentFg)
                Text(pendingCount == 1 ? "conversation blocked" : "conversations blocked")
                    .font(.dsSansPt(13.5, weight: .medium))
                    .foregroundStyle(t.accentFg.opacity(0.92))
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(t.accentFg.opacity(0.9))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pendingCount) conversations blocked, waiting on you")
    }

    // MARK: - Pending grouping (board: NEEDS YOUR APPROVAL / PATCH REVIEW)

    private struct PendingGroup { let label: String; let approvals: [Approval] }

    private var pendingGroups: [PendingGroup] {
        let pending = visibleApprovals.filter { $0.isPending }
        let patches = pending.filter { $0.kind == .patch }
        let rest = pending.filter { $0.kind != .patch }
        var groups: [PendingGroup] = []
        if !rest.isEmpty { groups.append(PendingGroup(label: "Needs your approval", approvals: rest)) }
        if !patches.isEmpty { groups.append(PendingGroup(label: "Patch review", approvals: patches)) }
        return groups
    }

    // MARK: - Pending card dispatch

    @ViewBuilder
    private func pendingCard(_ approval: Approval) -> some View {
        let isCritical = approval.risk.rawValue >= 3
        InboxBoardCard(
            bandLabel: bandLabel(for: approval),
            agentInitial: agentInitial(approval.agent),
            agentName: agentName(approval.agent),
            submeta: submeta(for: approval),
            riskLabel: riskLabel(approval.risk),
            riskColor: t.risk(approval.risk.rawValue),
            riskBackground: t.riskSoft(approval.risk.rawValue),
            bodyLead: bodyLead(for: approval),
            codeFragment: codeFragment(for: approval),
            bodyTail: bodyTail(for: approval),
            isCritical: isCritical,
            primaryLabel: approval.kind == .askQuestion ? "Answer" : "Approve",
            secondaryLabel: approval.kind == .patch ? "Review diff" : "Deny",
            onPrimary: {
                if isCritical {
                    Task {
                        do { try await BiometricGate.shared.unlock(reason: "Authenticate to approve a critical action") }
                        catch {
                            if let ce = error as? ConduitCore.ConduitError, case .cancelled = ce { return }
                            Haptics.error()
                            return
                        }
                        vm.decide(approval.id, decision: .approved)
                        Haptics.success()
                    }
                } else {
                    vm.decide(approval.id, decision: .approved)
                    Haptics.success()
                }
            },
            onSecondary: {
                // Patch review opens the detail sheet (with diff); everything else denies.
                if approval.kind == .patch {
                    detailApproval = approval
                } else {
                    vm.decide(approval.id, decision: .rejected)
                }
            },
            onOpenDetails: { detailApproval = approval }
        )
    }

    // MARK: - Board card content mapping

    private func bandLabel(for approval: Approval) -> String {
        approval.kind == .patch ? "Patch review" : "Needs your approval"
    }

    private func agentInitial(_ source: Approval.AgentSource) -> String {
        switch source {
        case .claudeCode: return "C"
        case .codex:      return "Cx"
        case .cursor:     return "Cu"
        case .opencode:   return "O"
        case .devin:      return "D"
        case .unknown:    return "A"
        }
    }

    private func submeta(for approval: Approval) -> String {
        let host = lastPathComponent(approval.cwd)
        return "\(host) · \(pendingTimeLabel(approval))"
    }

    private func lastPathComponent(_ path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        let comp = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        return comp.isEmpty ? path : comp
    }

    private func riskLabel(_ risk: Approval.Risk) -> String {
        switch risk {
        case .low:      return "LOW"
        case .medium:   return "MEDIUM"
        case .high:     return "HIGH RISK"
        case .critical: return "CRITICAL"
        }
    }

    /// The board renders the body as "lead text  <mono code chip>  tail text".
    /// For questions there is no command, so the whole question becomes the lead.
    private func bodyLead(for approval: Approval) -> String {
        switch approval.kind {
        case .askQuestion:
            return approval.question ?? "What should I do next?"
        case .patch:
            return "Apply a patch to"
        case .fileWrite:
            return "Wants to write"
        case .fileDelete:
            return "Wants to delete"
        case .network:
            return "Wants to reach"
        case .credential:
            return "Wants to access"
        case .browser:
            return "Wants to run a browser action on"
        case .callMCP:
            return "Wants to call"
        case .command:
            return "Wants to run"
        }
    }

    private func codeFragment(for approval: Approval) -> String? {
        switch approval.kind {
        case .askQuestion:
            return nil
        case .patch:
            return approval.toolName ?? "the working tree"
        default:
            return approval.command ?? approval.toolName ?? summarizedToolInput(approval)
        }
    }

    private func bodyTail(for approval: Approval) -> String? {
        switch approval.kind {
        case .command:    return "in the project root."
        case .patch:      return nil
        case .fileWrite,
             .fileDelete: return "in the project."
        default:          return nil
        }
    }

    // MARK: - Detail sheet

    @ViewBuilder
    private func detailSheet(_ approval: Approval) -> some View {
        let isCritical = approval.risk.rawValue >= 3
        let br = approval.blastRadius ?? ApprovalBlastRadius(matchedRule: "policy rule")
        VStack(spacing: 0) {
            InboxApprovalDetail(
                agentKey: agentKey(approval.agent),
                agentName: agentName(approval.agent),
                hostLabel: approval.cwd,
                cwd: approval.cwd,
                sessionID: approval.sessionID.uuidString,
                timeLabel: pendingTimeLabel(approval),
                question: approval.kind == .askQuestion ? (approval.question ?? "What should I do next?") : nil,
                toolName: approval.toolName ?? approval.command,
                args: approval.kind != .askQuestion ? summarizedToolInput(approval) : nil,
                command: approval.command,
                risk: approval.risk.rawValue,
                isCritical: isCritical,
                matchedRule: br.matchedRule,
                onDeny: {
                    vm.decide(approval.id, decision: .rejected)
                    detailApproval = nil
                },
                onEditAndRun: (approval.toolInput != nil || approval.command != nil) ? {
                    editedToolInputText = editableToolInput(for: approval)
                    editingApproval = approval
                    detailApproval = nil
                } : nil,
                onAllowAlways: {
                    Task {
                        if isCritical {
                            do { try await BiometricGate.shared.unlock(reason: "Authenticate to create an allow-always rule") }
                            catch {
                                if let ce = error as? ConduitCore.ConduitError, case .cancelled = ce { return }
                                Haptics.error()
                                return
                            }
                        }
                        detailApproval = nil
                        scopeSheetApproval = approval
                    }
                },
                onApprove: {
                    Task {
                        if isCritical {
                            do { try await BiometricGate.shared.unlock(reason: "Authenticate to approve a critical action") }
                            catch {
                                if let ce = error as? ConduitCore.ConduitError, case .cancelled = ce { return }
                                Haptics.error()
                                return
                            }
                        }
                        vm.decide(approval.id, decision: .approved)
                        Haptics.success()
                        detailApproval = nil
                    }
                }
            )

            if approval.kind == .patch, let patch = approval.patch {
                let diff = UnifiedDiffParser.parse(patch)
                if !diff.files.isEmpty {
                    DiffView(diff: diff)
                        .frame(maxHeight: 280)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Edit sheet

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

    // MARK: - Helpers

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

    // MARK: - Computed

    private var visibleApprovals: [Approval] {
        guard let sessionID else { return vm.effectiveApprovals }
        return vm.effectiveApprovals.filter { $0.sessionID == sessionID }
    }

    private var pendingCount: Int {
        visibleApprovals.filter { $0.isPending }.count
    }

    // MARK: - Home dashboard (shown when nothing is pending)

    private var handledTodayCount: Int {
        let cal = Calendar.current
        return visibleApprovals.filter { a in
            guard let decided = a.decidedAt else { return false }
            return cal.isDateInToday(decided)
        }.count
    }

    private var lastDecision: Approval? {
        visibleApprovals
            .filter { $0.decidedAt != nil }
            .max { ($0.decidedAt ?? .distantPast) < ($1.decidedAt ?? .distantPast) }
    }

    @ViewBuilder
    private var inboxHomeDashboard: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                VStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(t.okSoft)
                        Image(systemName: "checkmark")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(t.ok)
                    }
                    .frame(width: 60, height: 60)

                    Text("You're all caught up")
                        .font(.dsDisplayPt(21, weight: .bold))
                        .foregroundStyle(t.text)
                    Text("Every agent is cleared to run. Nice.")
                        .font(.dsSansPt(13))
                        .foregroundStyle(t.text4)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 30)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    dashboardStat(value: "\(handledTodayCount)", label: "handled today")
                    dashboardStat(
                        value: lastDecision.map { ($0.decision == .approved ? "approved" : "denied") } ?? "—",
                        label: "last decision"
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 26)

                if onOpenHistory != nil {
                    Button {
                        Haptics.selection()
                        onOpenHistory?()
                    } label: {
                        HStack(spacing: 8) {
                            DSIconView(.hourglass, size: 15, color: t.text2)
                            Text("View decision history")
                                .font(.dsSansPt(14, weight: .semibold))
                                .foregroundStyle(t.text2)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(t.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 18)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func dashboardStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.dsDisplayPt(24, weight: .bold))
                .foregroundStyle(t.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.dsMonoPt(10, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(t.text4)
                .textCase(.uppercase)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(t.border, lineWidth: 1))
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

    /// Absolute time-of-day plus a relative "waiting Nm" staleness hint for
    /// pending approvals, derived from `lastStateChangeAt` (falling back to
    /// `createdAt` when the daemon never stamped a state-change time).
    private func pendingTimeLabel(_ approval: Approval) -> String {
        let absolute = approval.createdAt.formatted(date: .omitted, time: .shortened)
        guard approval.isPending else { return absolute }
        let since = approval.lastStateChangeAt ?? approval.createdAt
        let elapsed = max(0, Date().timeIntervalSince(since))
        guard let waited = waitingHint(elapsed) else { return absolute }
        return "\(absolute) · waiting \(waited)"
    }

    private func waitingHint(_ seconds: TimeInterval) -> String? {
        guard seconds >= 60 else { return nil }
        let minutes = Int(seconds) / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remMin = minutes % 60
        return remMin == 0 ? "\(hours)h" : "\(hours)h \(remMin)m"
    }
}

private func persistAllowAlwaysRule(for approval: Approval) {
    let key = "inbox.allowAlwaysRules"
    var rules: [[String: String]] = (UserDefaults.standard.array(forKey: key) as? [[String: String]]) ?? []
    let entry: [String: String] = [
        "command": approval.command ?? "",
        "toolName": approval.toolName ?? "",
        "cwd": approval.cwd,
        "risk": String(approval.risk.rawValue),
        "agent": String(describing: approval.agent),
    ]
    rules.append(entry)
    UserDefaults.standard.set(rules, forKey: key)
}

private func persistScopedAllowAlwaysRule(for approval: Approval, rule: ScopedAllowRule) {
    let key = "inbox.allowAlwaysRules"
    var rules: [[String: String]] = (UserDefaults.standard.array(forKey: key) as? [[String: String]]) ?? []

    var entry: [String: String] = [
        "command": approval.command ?? "",
        "toolName": approval.toolName ?? "",
        "cwd": approval.cwd,
        "risk": String(approval.risk.rawValue),
        "agent": String(describing: approval.agent),
        "scope": rule.scope.rawValue,
    ]

    if let pathPattern = rule.pathPattern {
        entry["pathPattern"] = pathPattern
    }
    if let repoPattern = rule.repoPattern {
        entry["repoPattern"] = repoPattern
    }

    switch rule.timeWindow {
    case .untilRevoke:
        break
    case .hours(let h):
        let expiry = Calendar.current.date(byAdding: .hour, value: h, to: Date()) ?? Date()
        entry["expiresAt"] = ISO8601DateFormatter().string(from: expiry)
    case .days(let d):
        let expiry = Calendar.current.date(byAdding: .day, value: d, to: Date()) ?? Date()
        entry["expiresAt"] = ISO8601DateFormatter().string(from: expiry)
    }

    rules.append(entry)
    UserDefaults.standard.set(rules, forKey: key)
}

private func buildPolicyYAML(for approval: Approval, rule: ScopedAllowRule) -> String {
    var lines: [String] = []
    lines.append("rules:")

    let ruleID = "allow-\(approval.kind.rawValue)-\(UUID().uuidString.prefix(8))"
    lines.append("  - id: \"\(ruleID)\"")
    lines.append("    effect: allow")
    lines.append("    agent: \"\(approval.agent.rawValue)\"")
    lines.append("    kind: \"\(approval.kind.rawValue)\"")

    switch rule.scope {
    case .thisCommand:
        if let cmd = approval.command {
            lines.append("    match: \"\(cmd)\"")
        }
    case .thisCommandInRepo:
        lines.append("    cwd: \"\(approval.cwd)\"")
        if let cmd = approval.command {
            lines.append("    match: \"\(cmd)\"")
        }
    case .thisCommandMatchingPath:
        if let pattern = rule.pathPattern {
            lines.append("    pathPattern: \"\(pattern)\"")
        }
        if let cmd = approval.command {
            lines.append("    match: \"\(cmd)\"")
        }
    case .thisKindFromAgent:
        break
    }

    switch rule.timeWindow {
    case .untilRevoke:
        break
    case .hours(let h):
        let expiry = Calendar.current.date(byAdding: .hour, value: h, to: Date()) ?? Date()
        lines.append("    expiresAt: \"\(ISO8601DateFormatter().string(from: expiry))\"")
    case .days(let d):
        let expiry = Calendar.current.date(byAdding: .day, value: d, to: Date()) ?? Date()
        lines.append("    expiresAt: \"\(ISO8601DateFormatter().string(from: expiry))\"")
    }

    return lines.joined(separator: "\n")
}

// MARK: - Board-faithful approval card

/// Pixel-faithful reproduction of the design board's Inbox approval card:
/// a per-card band header (pulse dot + uppercase-mono label), an agent row
/// (square initial tile, name, "machine · time" submeta, risk badge), a body
/// line with the command rendered as an inline mono chip, and two buttons —
/// dark-filled primary + outlined secondary.
private struct InboxBoardCard: View {
    let bandLabel: String
    let agentInitial: String
    let agentName: String
    let submeta: String
    let riskLabel: String
    let riskColor: Color
    let riskBackground: Color
    let bodyLead: String
    let codeFragment: String?
    let bodyTail: String?
    let isCritical: Bool
    let primaryLabel: String
    let secondaryLabel: String
    let onPrimary: () -> Void
    let onSecondary: () -> Void
    let onOpenDetails: () -> Void

    @Environment(\.conduitTokens) private var t

    var body: some View {
        VStack(spacing: 0) {
            bandHeader
            cardBody
        }
        .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(t.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 2)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var bandHeader: some View {
        HStack(spacing: 7) {
            DSStatusDot(tone: .warn, pulse: true, size: 6)
            Text(bandLabel.uppercased())
                .font(.dsMonoPt(10, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(t.text3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface2)
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Text(agentInitial)
                    .font(.dsDisplayPt(13, weight: .bold))
                    .foregroundStyle(t.accentFg)
                    .frame(width: 30, height: 30)
                    .background(t.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(agentName)
                        .font(.dsSansPt(14, weight: .semibold))
                        .foregroundStyle(t.text)
                    Text(submeta)
                        .font(.dsSansPt(11.5))
                        .foregroundStyle(t.text4)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(riskLabel)
                    .font(.dsMonoPt(10, weight: .semibold))
                    .foregroundStyle(riskColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(riskBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            bodyLine

            if isCritical {
                Label("Face ID required to approve", systemImage: "faceid")
                    .font(.dsSansPt(12, weight: .medium))
                    .foregroundStyle(t.warn)
            }

            HStack(spacing: 9) {
                Button(action: { Haptics.selection(); onPrimary() }) {
                    Text(primaryLabel)
                        .font(.dsSansPt(13.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(t.surface)
                        .background(t.text, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: { Haptics.selection(); onSecondary() }) {
                    Text(secondaryLabel)
                        .font(.dsSansPt(13.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(t.text3)
                        .background(t.surface2, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(t.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture { onOpenDetails() }
    }

    /// "<lead> <mono chip> <tail>" rendered as wrapping inline text so the
    /// command reads as a code fragment exactly like the board.
    private var bodyLine: some View {
        let lead = Text(bodyLead + (codeFragment != nil ? " " : ""))
            .font(.dsSansPt(13))
            .foregroundStyle(t.text2)
        let code = codeFragment.map { frag in
            Text(frag)
                .font(.dsMonoPt(11.5))
                .foregroundStyle(t.accent)
        } ?? Text("")
        let tail = bodyTail.map { Text(" " + $0).font(.dsSansPt(13)).foregroundStyle(t.text2) } ?? Text("")
        return (lead + code + tail)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel([bodyLead, codeFragment, bodyTail].compactMap { $0 }.joined(separator: " "))
    }
}

#endif
