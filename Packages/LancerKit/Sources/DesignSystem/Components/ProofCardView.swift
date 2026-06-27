import SwiftUI
import LancerCore

// MARK: - ProofCardModel

public struct ProofCardModel: Identifiable, Sendable {
    public let id: String
    public let agent: AgentKey
    public let agentName: String
    public let status: Status
    public let duration: String?

    public var tests: TestResults?
    public var diff: DiffSummary?
    public var commands: [String]
    public var approvals: ApprovalSummary?
    public var policyExceptions: Int
    public var spend: SpendSummary?
    public var prURL: String?
    public var prNumber: Int?
    public var ciEvents: [CIEvent]?

    public enum Status: Sendable {
        case completed
        case failed
        case cancelled
    }

    public struct TestResults: Sendable {
        public let passed: Int
        public let failed: Int
        public let failedNames: [String]

        public init(passed: Int, failed: Int, failedNames: [String] = []) {
            self.passed = passed
            self.failed = failed
            self.failedNames = failedNames
        }
    }

    public struct DiffSummary: Sendable {
        public let filesChanged: Int
        public let insertions: Int
        public let deletions: Int
        public let fileNames: [String]

        public init(filesChanged: Int, insertions: Int, deletions: Int, fileNames: [String] = []) {
            self.filesChanged = filesChanged
            self.insertions = insertions
            self.deletions = deletions
            self.fileNames = fileNames
        }
    }

    public struct ApprovalSummary: Sendable {
        public let asked: Int
        public let approved: Int
        public let denied: Int

        public init(asked: Int, approved: Int, denied: Int) {
            self.asked = asked
            self.approved = approved
            self.denied = denied
        }
    }

    public struct SpendSummary: Sendable {
        public let totalUSD: Double
        public let inputTokens: Int?
        public let outputTokens: Int?

        public init(totalUSD: Double, inputTokens: Int? = nil, outputTokens: Int? = nil) {
            self.totalUSD = totalUSD
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
        }
    }

    public init(
        id: String = UUID().uuidString,
        agent: AgentKey,
        agentName: String,
        status: Status,
        duration: String? = nil,
        tests: TestResults? = nil,
        diff: DiffSummary? = nil,
        commands: [String] = [],
        approvals: ApprovalSummary? = nil,
        policyExceptions: Int = 0,
        spend: SpendSummary? = nil,
        prURL: String? = nil,
        prNumber: Int? = nil,
        ciEvents: [CIEvent]? = nil
    ) {
        self.id = id
        self.agent = agent
        self.agentName = agentName
        self.status = status
        self.duration = duration
        self.tests = tests
        self.diff = diff
        self.commands = commands
        self.approvals = approvals
        self.policyExceptions = policyExceptions
        self.spend = spend
        self.prURL = prURL
        self.prNumber = prNumber
        self.ciEvents = ciEvents
    }
}

// MARK: - ProofCardView

public struct ProofCardView: View {
    let model: ProofCardModel
    let onPRTap: (() -> Void)?

    @State private var commandsExpanded = false

    private let maxVisibleCommands = 3

    @Environment(\.lancerTokens) private var t

    public init(model: ProofCardModel, onPRTap: (() -> Void)? = nil) {
        self.model = model
        self.onPRTap = onPRTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            divider
            sections
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            AgentIdentityBadge(agent: model.agent, label: model.agentName)
            statusChip
            Spacer()
            if let dur = model.duration {
                Text(dur)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statusChip: some View {
        switch model.status {
        case .completed:
            DSChip("Completed", tone: .ok, variant: .soft, size: .sm)
        case .failed:
            DSChip("Failed", tone: .danger, variant: .soft, size: .sm)
        case .cancelled:
            DSChip("Cancelled", tone: .neutral, variant: .soft, size: .sm)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var sections: some View {
        if let tests = model.tests {
            testSection(tests)
            divider
        }

        if let diff = model.diff {
            diffSection(diff)
            divider
        }

        if !model.commands.isEmpty {
            commandsSection
            divider
        }

        if let approvals = model.approvals {
            approvalSection(approvals)
            divider
        }

        if model.policyExceptions > 0 {
            policyExceptionSection
            divider
        }

        if let spend = model.spend {
            spendSection(spend)
        }

        if let prNumber = model.prNumber {
            prSection(prNumber)
        }

        if let ciEvents = model.ciEvents, !ciEvents.isEmpty {
            divider
            ciChecksSection(ciEvents)
        }
    }

    // MARK: - Test Results

    private func testSection(_ tests: ProofCardModel.TestResults) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Tests")
                    .font(.dsSansPt(12, weight: .semibold))
                    .foregroundStyle(t.text)
                if tests.failed > 0 {
                    DSChip("\(tests.passed) passed", tone: .ok, variant: .soft, size: .sm)
                    DSChip("\(tests.failed) failed", tone: .danger, variant: .soft, size: .sm)
                } else {
                    DSChip("\(tests.passed) passed", tone: .ok, variant: .soft, size: .sm)
                }
            }
            if !tests.failedNames.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(tests.failedNames, id: \.self) { name in
                        HStack(spacing: 4) {
                            DSIconView(.close, size: 10, color: t.danger)
                            Text(name)
                                .font(.dsMonoPt(11))
                                .foregroundStyle(t.text2)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Diff Summary

    private func diffSection(_ diff: ProofCardModel.DiffSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Diff")
                    .font(.dsSansPt(12, weight: .semibold))
                    .foregroundStyle(t.text)
                Text("\(diff.filesChanged) file\(diff.filesChanged == 1 ? "" : "s") changed")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text2)
                DSChip("+\(diff.insertions)", tone: .ok, variant: .soft, size: .sm)
                DSChip("-\(diff.deletions)", tone: .danger, variant: .soft, size: .sm)
            }
            if !diff.fileNames.isEmpty {
                let visible = Array(diff.fileNames.prefix(5))
                let remaining = diff.fileNames.count - visible.count
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(visible, id: \.self) { name in
                        HStack(spacing: 4) {
                            DSIconView(.file, size: 10, color: t.text3)
                            Text(name)
                                .font(.dsMonoPt(11))
                                .foregroundStyle(t.text2)
                                .lineLimit(1)
                        }
                    }
                    if remaining > 0 {
                        Text("+\(remaining) more")
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text3)
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Commands

    private var commandsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Commands")
                .font(.dsSansPt(12, weight: .semibold))
                .foregroundStyle(t.text)

            let visibleCount = commandsExpanded ? model.commands.count : min(model.commands.count, maxVisibleCommands)
            let visibleCommands = Array(model.commands.prefix(visibleCount))

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleCommands.enumerated()), id: \.offset) { idx, cmd in
                    DSQuoteBlock(
                        title: "$",
                        tags: [],
                        message: cmd,
                        tone: .neutral
                    )
                    .font(.dsMonoPt(12))
                    if idx < visibleCommands.count - 1 {
                        Rectangle().fill(t.divider).frame(height: 1)
                    }
                }
            }

            if model.commands.count > maxVisibleCommands {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        commandsExpanded.toggle()
                    }
                } label: {
                    Text(commandsExpanded ? "Show less" : "+\(model.commands.count - maxVisibleCommands) more")
                        .font(.dsMonoPt(11, weight: .medium))
                        .foregroundStyle(t.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Approvals

    private func approvalSection(_ approvals: ProofCardModel.ApprovalSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Approvals")
                    .font(.dsSansPt(12, weight: .semibold))
                    .foregroundStyle(t.text)
                DSChip("\(approvals.asked) asked", tone: .neutral, variant: .soft, size: .sm)
                if approvals.approved > 0 {
                    DSChip("\(approvals.approved) approved", tone: .ok, variant: .soft, size: .sm)
                }
                if approvals.denied > 0 {
                    DSChip("\(approvals.denied) denied", tone: .danger, variant: .soft, size: .sm)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Policy Exceptions

    private var policyExceptionSection: some View {
        HStack(spacing: 6) {
            DSIconView(.alertTri, size: 12, color: t.warn)
            Text("\(model.policyExceptions) policy exception\(model.policyExceptions == 1 ? "" : "s")")
                .font(.dsMonoPt(11, weight: .medium))
                .foregroundStyle(t.warn)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.warnSoft)
        .overlay(alignment: .leading) {
            Rectangle().fill(t.warn).frame(width: 3)
        }
    }

    // MARK: - Spend

    private func spendSection(_ spend: ProofCardModel.SpendSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Spend")
                    .font(.dsSansPt(12, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(String(format: "$%.2f", spend.totalUSD))
                    .font(.dsMonoPt(13, weight: .semibold))
                    .foregroundStyle(t.text)
            }
            if let input = spend.inputTokens, let output = spend.outputTokens {
                HStack(spacing: 8) {
                    Text("\(input.formatted()) in")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                    Text("\(output.formatted()) out")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - PR Link

    private func prSection(_ number: Int) -> some View {
        HStack(spacing: 6) {
            DSIconView(.link, size: 12, color: t.accent)
            DSLink("PR #\(number)", action: { onPRTap?() })
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - CI Checks

    private func ciChecksSection(_ events: [CIEvent]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Checks")
                    .font(.dsSansPt(12, weight: .semibold))
                    .foregroundStyle(t.text)
                let passing = events.filter { $0.status == .success }.count
                let failing = events.filter { $0.status == .failure }.count
                let pending = events.filter { $0.status == .pending }.count
                if passing > 0 {
                    DSChip("\(passing) passed", tone: .ok, variant: .soft, size: .sm)
                }
                if failing > 0 {
                    DSChip("\(failing) failed", tone: .danger, variant: .soft, size: .sm)
                }
                if pending > 0 {
                    DSChip("\(pending) pending", tone: .warn, variant: .soft, size: .sm)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(events.prefix(5)) { event in
                    HStack(spacing: 4) {
                        Image(systemName: event.statusIcon)
                            .font(.system(size: 9))
                            .foregroundStyle(ciStatusColor(event.status))
                        Text(event.context ?? "check")
                            .font(.dsMonoPt(10))
                            .foregroundStyle(t.text2)
                            .lineLimit(1)
                        Spacer()
                        Text(event.statusLabel)
                            .font(.dsMonoPt(9))
                            .foregroundStyle(ciStatusColor(event.status))
                    }
                }
                if events.count > 5 {
                    Text("+\(events.count - 5) more")
                        .font(.dsMonoPt(9))
                        .foregroundStyle(t.text3)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func ciStatusColor(_ status: CIEvent.CheckStatus) -> some ShapeStyle {
        switch status {
        case .success: return t.ok
        case .failure: return t.danger
        case .pending: return t.warn
        case .error:   return t.danger
        }
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle().fill(t.divider).frame(height: 1)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ScrollView {
        VStack(spacing: 16) {
            ProofCardView(model: ProofCardModel(
                agent: .claudeCode,
                agentName: "Claude Code",
                status: .completed,
                duration: "4m 12s",
                tests: .init(passed: 12, failed: 0),
                diff: .init(filesChanged: 3, insertions: 42, deletions: 18, fileNames: [
                    "Sources/App.swift", "Sources/Models/User.swift", "Tests/UserTests.swift"
                ]),
                commands: ["swift build", "swift test", "git diff --stat"],
                approvals: .init(asked: 8, approved: 7, denied: 1),
                policyExceptions: 0,
                spend: .init(totalUSD: 2.47, inputTokens: 14_200, outputTokens: 3_800),
                prNumber: 123
            ))

            ProofCardView(model: ProofCardModel(
                agent: .codex,
                agentName: "Codex",
                status: .failed,
                duration: "1m 03s",
                tests: .init(passed: 10, failed: 2, failedNames: ["testAuthFlow", "testTokenRefresh"]),
                diff: .init(filesChanged: 1, insertions: 8, deletions: 3, fileNames: ["src/auth.ts"]),
                commands: ["npm test"],
                approvals: .init(asked: 2, approved: 2, denied: 0),
                policyExceptions: 1,
                spend: .init(totalUSD: 0.34)
            ))
        }
        .padding(16)
    }
    .background(LancerTokens.dark.bg)
}
#endif
