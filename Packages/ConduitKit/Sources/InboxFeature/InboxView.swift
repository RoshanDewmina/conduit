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

    @Environment(\.conduitTokens) private var t
    @State private var detailApproval: Approval?
    @State private var editingApproval: Approval?
    @State private var editedToolInputText = ""
    @State private var scopeSheetApproval: Approval?

    public init(
        viewModel: InboxViewModel,
        sessionID: SessionID? = nil,
        title: String = "Inbox",
        awayAuditEntries: [AuditLogEntry] = [],
        statusHeaderAgents: [AgentInfo] = [],
        onTapStatusHeader: @escaping () -> Void = {},
        onSetPolicy: ((String) async -> Void)? = nil
    ) {
        self.vm = viewModel
        self.sessionID = sessionID
        self.title = title
        self.awayAuditEntries = awayAuditEntries
        self.statusHeaderAgents = statusHeaderAgents
        self.onTapStatusHeader = onTapStatusHeader
        self.onSetPolicy = onSetPolicy
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Big typography header
                HStack {
                    Text("inbox")
                        .font(.dsDisplayPt(32, weight: .bold))
                        .foregroundStyle(t.text)
                    Spacer()
                    if pendingCount > 0 {
                        Text("\(pendingCount) pending")
                            .font(.dsMonoPt(13))
                            .foregroundStyle(t.text3)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                if visibleApprovals.isEmpty {
                    InboxEmptyState()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            let pending = visibleApprovals.filter { $0.isPending }

                            if !pending.isEmpty {
                                ForEach(pending) { approval in
                                    pendingCard(approval)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        .padding(.bottom, 16)
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
    }

    // MARK: - Pending card dispatch

    @ViewBuilder
    private func pendingCard(_ approval: Approval) -> some View {
        let isCritical = approval.risk.rawValue >= 3
        InboxApprovalCard(
            agentKey: agentKey(approval.agent),
            agentName: agentName(approval.agent),
            timeLabel: pendingTimeLabel(approval),
            question: approval.kind == .askQuestion ? (approval.question ?? "What should I do next?") : nil,
            toolName: approval.toolName ?? approval.command,
            args: approval.kind != .askQuestion ? summarizedToolInput(approval) : nil,
            risk: approval.risk.rawValue,
            isCritical: isCritical,
            onDeny: { vm.decide(approval.id, decision: .rejected) },
            onApprove: {
                if isCritical {
                    Task {
                        do { try await BiometricGate.shared.unlock(reason: "Authenticate to approve a critical action") }
                        catch {
                            if let ce = error as? ConduitCore.ConduitError, case .cancelled = ce { return }
                            return
                        }
                        vm.decide(approval.id, decision: .approved)
                        Haptics.success()
                    }
                } else {
                    vm.decide(approval.id, decision: .approved)
                }
            }
        )
        .onTapGesture { detailApproval = approval }
    }

    // MARK: - Detail sheet

    @ViewBuilder
    private func detailSheet(_ approval: Approval) -> some View {
        let isCritical = approval.risk.rawValue >= 3
        let br = approval.blastRadius ?? ApprovalBlastRadius(matchedRule: "policy rule")
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
                            return
                        }
                    }
                    vm.decide(approval.id, decision: .approved)
                    Haptics.success()
                    detailApproval = nil
                }
            }
        )
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

    private func defaultActionVerb(for kind: Approval.Kind) -> String {
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

#endif
