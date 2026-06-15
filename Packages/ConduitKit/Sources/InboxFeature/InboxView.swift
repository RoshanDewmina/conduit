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

    public var demoDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: "inbox.demoDismissed") }
        set { UserDefaults.standard.set(newValue, forKey: "inbox.demoDismissed") }
    }

    public var demoApproval: Approval {
        Approval(
            id: ApprovalID(),
            sessionID: SessionID(),
            agent: .claudeCode,
            kind: .command,
            command: "npm install && npm run build",
            patch: nil,
            cwd: "~/projects/my-app",
            risk: .medium,
            createdAt: .now,
            toolName: "bash",
            toolInput: nil,
            blastRadius: ApprovalBlastRadius(
                files: ["package.json"],
                touchesGit: false,
                touchesNetwork: true,
                matchedRule: "auto-allow-safe-commands"
            )
        )
    }

    public var effectiveApprovals: [Approval] {
        if approvals.isEmpty && !demoDismissed {
            return [demoApproval]
        }
        return approvals
    }

    public func dismissDemo() {
        demoDismissed = true
    }

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
    public var bridgeConnected: Bool = false
    public var bridgePolicy: String = "balanced"
    public var todaySpend: String = "$0.00"
    public var onSetPolicy: ((String) async -> Void)?

    @Environment(\.conduitTokens) private var t
    @State private var editingApproval: Approval?
    @State private var editedToolInputText = ""
    @State private var diffApproval: Approval?
    @State private var decisionSheetApproval: Approval?
    @State private var scopeSheetApproval: Approval?

    public init(
        viewModel: InboxViewModel,
        sessionID: SessionID? = nil,
        title: String = "Inbox",
        awayAuditEntries: [AuditLogEntry] = [],
        statusHeaderAgents: [AgentInfo] = [],
        onTapStatusHeader: @escaping () -> Void = {},
        bridgeConnected: Bool = false,
        bridgePolicy: String = "balanced",
        todaySpend: String = "$0.00",
        onSetPolicy: ((String) async -> Void)? = nil
    ) {
        self.vm = viewModel
        self.sessionID = sessionID
        self.title = title
        self.awayAuditEntries = awayAuditEntries
        self.statusHeaderAgents = statusHeaderAgents
        self.onTapStatusHeader = onTapStatusHeader
        self.bridgeConnected = bridgeConnected
        self.bridgePolicy = bridgePolicy
        self.todaySpend = todaySpend
        self.onSetPolicy = onSetPolicy
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                DSStatusHeader(
                    connected: bridgeConnected,
                    policy: bridgePolicy,
                    todaySpend: todaySpend
                )

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

                if visibleApprovals.isEmpty && !vm.demoDismissed {
                    VStack {
                        Spacer()
                        DSEmptyState(
                            dotMatrix: .thinking,
                            title: "Your first approval",
                            subtitle: "This is a demo. When you connect a coding agent, its permission requests appear here. Tap the card to see the full decision sheet."
                        )
                        .padding(.horizontal, 24)
                        pendingCard(vm.demoApproval)
                            .padding(.horizontal, 16)
                        Spacer()
                    }
                } else if visibleApprovals.isEmpty {
                    VStack {
                        Spacer()
                        DSEmptyState(
                            dotMatrix: .idle,
                            title: "No approvals waiting",
                            subtitle: "When a coding agent needs permission, its request will appear here."
                        )
                        .padding(.horizontal, 24)
                        Spacer()
                    }
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
        .sheet(item: $decisionSheetApproval) { approval in
            decisionSheetContent(approval)
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
        let isDemo = vm.approvals.isEmpty && !vm.demoDismissed

        switch approval.kind {
        case .askQuestion:
            DSAskQuestionCard(
                agentKey: agentKey(approval.agent),
                agentName: agentName(approval.agent),
                hostLabel: approval.cwd,
                timeLabel: pendingTimeLabel(approval),
                question: approval.question ?? "What should I do next?",
                choices: approval.choices ?? [],
                onAnswer: { idx in
                    if isDemo { vm.dismissDemo() }
                    else { vm.decide(approval.id, decision: .approved, choiceIndex: idx) }
                }
            )

        case .callMCP:
            DSMCPCallCard(
                agentKey: agentKey(approval.agent),
                agentName: agentName(approval.agent),
                hostLabel: approval.cwd,
                timeLabel: pendingTimeLabel(approval),
                toolName: approval.toolName ?? approval.command ?? "unknown_tool",
                toolUseID: approval.toolUseID,
                args: summarizedToolInput(approval),
                risk: approval.risk.rawValue,
                onDeny: { if isDemo { vm.dismissDemo() } else { vm.decide(approval.id, decision: .rejected) } },
                onEditAndRun: {
                    if isDemo { vm.dismissDemo() }
                    else {
                        editedToolInputText = editableToolInput(for: approval)
                        editingApproval = approval
                    }
                },
                onAllowAlways: { if isDemo { vm.dismissDemo() } else { scopeSheetApproval = approval } },
                onApprove: { if isDemo { vm.dismissDemo() } else { vm.decide(approval.id, decision: .approved) } }
            )
            .onTapGesture { decisionSheetApproval = approval }

        case .credential:
            DSCredentialRequestCard(
                agentKey: agentKey(approval.agent),
                agentName: agentName(approval.agent),
                hostLabel: approval.cwd,
                timeLabel: pendingTimeLabel(approval),
                toolName: approval.toolName ?? approval.command ?? "unknown",
                credentialHint: approval.command ?? "credential",
                risk: approval.risk.rawValue,
                onDeny: { if isDemo { vm.dismissDemo() } else { vm.decide(approval.id, decision: .rejected) } },
                onApprove: { if isDemo { vm.dismissDemo() } else { vm.decide(approval.id, decision: .approved) } },
                onAuthorizeScope: { if isDemo { vm.dismissDemo() } else { scopeSheetApproval = approval } }
            )

        default:
            VStack(alignment: .leading, spacing: 8) {
                DSApprovalCard(
                    agentKey: agentKey(approval.agent),
                    risk: approval.risk.rawValue,
                    timeLabel: pendingTimeLabel(approval),
                    agentName: agentName(approval.agent),
                    action: approval.toolName.map { "run \($0)" } ?? defaultActionVerb(for: approval.kind),
                    hostLabel: approval.cwd,
                    command: approval.command,
                    onViewDiff: (approval.patch != nil || approval.kind == .patch) ? { diffApproval = approval } : nil,
                    onDeny: { if isDemo { vm.dismissDemo() } else { vm.decide(approval.id, decision: .rejected) } },
                    onAllowAlways: { if isDemo { vm.dismissDemo() } else { scopeSheetApproval = approval } },
                    onEditAndRun: isDemo ? nil : ((approval.toolInput != nil || approval.command != nil) ? {
                        editedToolInputText = editableToolInput(for: approval)
                        editingApproval = approval
                    } : nil),
                    onApprove: { if isDemo { vm.dismissDemo() } else { vm.decide(approval.id, decision: .approved) } }
                )
                if let br = approval.blastRadius {
                    DSBlastRadiusBanner(blastRadius: br)
                }
            }
            .onTapGesture { decisionSheetApproval = approval }
        }
    }

    @ViewBuilder
    private func decisionSheetContent(_ approval: Approval) -> some View {
        let br = approval.blastRadius ?? ApprovalBlastRadius(matchedRule: "policy rule")
        let requiresBiometric = approval.risk.rawValue >= 3
        let agentNameStr = agentName(approval.agent)
        let actionStr: String = {
            if let tn = approval.toolName { return "run \(tn)" }
            return defaultActionVerb(for: approval.kind)
        }()
        let cmdStr = approval.command ?? approval.toolName ?? "Unknown command"
        let whyStr = br.matchedRule.map { "Matched policy rule \"\($0)\" requiring human approval." }
            ?? "This action requires human approval per your policy settings."
        let isDemo = vm.approvals.isEmpty && !vm.demoDismissed

        DSDecisionSheet(
            risk: approval.risk.rawValue,
            agentName: agentNameStr,
            action: actionStr,
            command: cmdStr,
            whyText: isDemo ? "This is a demo approval. In a real scenario, this text explains which policy rule matched the agent's action." : whyStr,
            requiresBiometric: requiresBiometric && !isDemo,
            diff: nil,
            blastRadius: br,
            onDeny: {
                if isDemo { vm.dismissDemo() } else { vm.decide(approval.id, decision: .rejected) }
                decisionSheetApproval = nil
            },
            onApprove: {
                Task {
                    if requiresBiometric && !isDemo {
                        do { try await BiometricGate.shared.unlock(reason: "Authenticate to approve a critical action") }
                        catch {
                            if let ce = error as? ConduitCore.ConduitError, case .cancelled = ce { return }
                            return
                        }
                    }
                    if isDemo { vm.dismissDemo() } else {
                        vm.decide(approval.id, decision: .approved)
                        Haptics.success()
                    }
                    decisionSheetApproval = nil
                }
            },
            onEditAndRun: {
                if isDemo { vm.dismissDemo() }
                else {
                    editedToolInputText = editableToolInput(for: approval)
                    editingApproval = approval
                }
                decisionSheetApproval = nil
            },
            onAllowAlways: {
                Task {
                    if requiresBiometric && !isDemo {
                        do { try await BiometricGate.shared.unlock(reason: "Authenticate to create an allow-always rule") }
                        catch {
                            if let ce = error as? ConduitCore.ConduitError, case .cancelled = ce { return }
                            return
                        }
                    }
                    if isDemo { vm.dismissDemo() } else {
                        decisionSheetApproval = nil
                        scopeSheetApproval = approval
                    }
                }
            }
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
                title: "No approvals waiting",
                subtitle: "When a coding agent needs permission, its request appears here and on your lock screen."
            )
            .padding(.horizontal, 24)
            Spacer()
        }
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

    private func decidedLabel(_ approval: Approval) -> String {
        if approval.kind == .askQuestion,
           let ci = approval.answeredChoice,
           let choices = approval.choices, ci < choices.count {
            return "Answered: \(choices[ci])"
        }
        return approval.command ?? defaultActionVerb(for: approval.kind)
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
