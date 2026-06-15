#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem
import DiffFeature
import DiffKit
import SSHTransport

public struct LoopDetailView: View {
    let loop: Loop
    let onDismiss: () -> Void
    let ciEventLoader: (@Sendable () async -> [CIEvent])?

    @State private var ciEvents: [CIEvent]
    /// Git review/ship store for this loop's worktree. nil when the loop has no
    /// worktree path or no connected host — the "Changes" section is then hidden.
    @State private var gitStore: GitStore?
    @State private var showShipSheet = false
    @State private var diffToReview: IdentifiableDiff?

    @Environment(\.conduitTokens) private var t
    @Environment(\.openURL) private var openURL

    public init(
        loop: Loop,
        onDismiss: @escaping () -> Void = {},
        ciEvents: [CIEvent] = [],
        ciEventLoader: (@Sendable () async -> [CIEvent])? = nil,
        gitStore: GitStore? = nil
    ) {
        self.loop = loop
        self.onDismiss = onDismiss
        _ciEvents = State(initialValue: ciEvents)
        self.ciEventLoader = ciEventLoader
        _gitStore = State(initialValue: gitStore)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                    statusSection
                    identitySection
                    locationSection
                    if gitStore != nil {
                        changesSection
                    }
                    progressSection
                    approvalsSection
                    spendSection
                    if let proof = loop.proof {
                        proofSection(proof)
                    }
                    if !ciEvents.isEmpty {
                        ciStatusSection
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Loop")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let ciEventLoader else { return }
            let fetched = await ciEventLoader()
            if !fetched.isEmpty { ciEvents = fetched }
        }
        .task(id: loop.id) {
            await gitStore?.refresh()
        }
        .sheet(item: $diffToReview) { wrapped in
            NavigationStack { DiffView(diff: wrapped.diff) }
        }
        .sheet(isPresented: $showShipSheet) {
            if let gitStore {
                ShipItSheet(store: gitStore, loop: loop) { openURL($0) }
            }
        }
    }

    // MARK: - Changes (review + ship the agent's git work)

    @ViewBuilder
    private var changesSection: some View {
        if let git = gitStore {
            VStack(alignment: .leading, spacing: 8) {
                DSListSectionHead("Changes")

                if let status = git.status {
                    HStack(spacing: 8) {
                        DSChip(status.branch, systemImage: "arrow.triangle.branch", tone: .accent, variant: .outlined, size: .sm)
                        if status.ahead > 0 {
                            DSChip("↑\(status.ahead)", tone: .info, variant: .soft, size: .sm)
                        }
                        if status.behind > 0 {
                            DSChip("↓\(status.behind)", tone: .warn, variant: .soft, size: .sm)
                        }
                        DSChip(status.isClean ? "clean" : "\(status.changes.count) changed",
                               tone: status.isClean ? .ok : .warn, variant: .soft, size: .sm)
                        Spacer()
                    }
                }

                if !git.changedFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(git.changedFiles.prefix(8)) { file in
                            HStack(spacing: 6) {
                                Image(systemName: "doc")
                                    .font(.system(size: 10))
                                    .foregroundStyle(t.text3)
                                Text(file.path)
                                    .font(.dsMonoPt(11))
                                    .foregroundStyle(t.text2)
                                    .lineLimit(1)
                                Spacer()
                                Text(file.status.rawValue)
                                    .font(.dsMonoPt(9))
                                    .foregroundStyle(t.text3)
                            }
                        }
                        if git.changedFiles.count > 8 {
                            Text("+\(git.changedFiles.count - 8) more")
                                .font(.dsMonoPt(10))
                                .foregroundStyle(t.text3)
                        }
                    }
                }

                if let err = git.error, !err.isEmpty {
                    Text(err)
                        .font(.dsMonoPt(10))
                        .foregroundStyle(t.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    DSButton("Review diff", variant: .secondary, size: .sm, mono: true) {
                        Task {
                            if let diff = await git.loadDiff() {
                                diffToReview = IdentifiableDiff(diff: diff)
                            }
                        }
                    }
                    DSButton("Ship it", variant: .primary, size: .sm, mono: true) {
                        showShipSheet = true
                    }
                    .disabled(git.isShipping)
                    Spacer()
                    if git.isLoading || git.isShipping {
                        ProgressView().scaleEffect(0.7)
                    }
                }
            }
        }
    }

    // MARK: - CI Status

    private var ciStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSListSectionHead("CI Status")

            let prEvents = ciEvents.filter { $0.type == .pullRequest }
            let checkEvents = ciEvents.filter { $0.type == .checkRun || $0.type == .status }

            if !prEvents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(prEvents.prefix(3)) { event in
                        HStack(spacing: 6) {
                            Image(systemName: event.statusIcon)
                                .font(.system(size: 10))
                                .foregroundStyle(statusColor(event.status))
                            Text("PR #\(event.prNumber ?? 0)")
                                .font(.dsMonoPt(11, weight: .medium))
                                .foregroundStyle(t.text)
                            Text(event.action)
                                .font(.dsMonoPt(10))
                                .foregroundStyle(t.text3)
                            Spacer()
                            Text(event.timestamp, style: .relative)
                                .font(.dsMonoPt(9))
                                .foregroundStyle(t.text3)
                        }
                    }
                }
            }

            if !checkEvents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(checkEvents.prefix(5)) { event in
                        HStack(spacing: 6) {
                            Image(systemName: event.statusIcon)
                                .font(.system(size: 10))
                                .foregroundStyle(statusColor(event.status))
                            Text(event.context ?? "check")
                                .font(.dsMonoPt(11))
                                .foregroundStyle(t.text)
                            Spacer()
                            Text(event.statusLabel)
                                .font(.dsMonoPt(10))
                                .foregroundStyle(statusColor(event.status))
                        }
                    }
                }
            }
        }
    }

    private func statusColor(_ status: CIEvent.CheckStatus) -> some ShapeStyle {
        switch status {
        case .success: return t.ok
        case .failure: return t.danger
        case .pending: return t.warn
        case .error:   return t.danger
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loop.goal)
                .font(.dsSansPt(18, weight: .semibold))
                .foregroundStyle(t.text)
                .fixedSize(horizontal: false, vertical: true)

            if let plan = loop.plan {
                Text(plan)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        HStack(spacing: 8) {
            DSChip(
                loop.status.rawValue,
                systemImage: statusIcon,
                tone: statusTone,
                variant: .outlined,
                size: .md
            )

            if let step = loop.currentStep {
                DSChip("Step: \(step)", tone: .info, variant: .default, size: .sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusIcon: String {
        switch loop.status {
        case .running:   return "bolt.fill"
        case .blocked:   return "pause.circle"
        case .paused:    return "pause.circle"
        case .completed: return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    private var statusTone: DSChipTone {
        switch loop.status {
        case .running:   return .ok
        case .blocked:   return .warn
        case .paused:    return .info
        case .completed: return .ok
        case .failed:    return .danger
        case .cancelled: return .neutral
        }
    }

    // MARK: - Identity

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            DSListSectionHead("Agent")
            HStack(spacing: 8) {
                DSChip(loop.agent, tone: .accent, variant: .solid, size: .md)
                if let vendor = loop.vendor {
                    DSChip(vendor, tone: .neutral, variant: .default, size: .sm)
                }
                if let model = loop.model {
                    DSChip(model, tone: .neutral, variant: .mono, size: .sm)
                }
            }
        }
    }

    // MARK: - Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            DSListSectionHead("Location")
            VStack(alignment: .leading, spacing: 4) {
                locationRow(icon: "server", label: "Host", value: loop.hostID)
                if let repo = loop.repo {
                    locationRow(icon: "folder", label: "Repo", value: repo)
                }
                if let branch = loop.branch {
                    locationRow(icon: "arrow.triangle.branch", label: "Branch", value: branch)
                }
                if let worktree = loop.worktree {
                    locationRow(icon: "folder.badge.gearshape", label: "Worktree", value: worktree)
                }
            }
        }
    }

    private func locationRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(t.text3)
                .frame(width: 16)
            Text(label)
                .font(.dsMonoPt(12, weight: .medium))
                .foregroundStyle(t.text3)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.dsMonoPt(12))
                .foregroundStyle(t.text)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSListSectionHead("Progress")

            HStack(spacing: 12) {
                progressStat(
                    icon: "doc.text",
                    label: "Files",
                    value: "\(loop.filesChanged.count)"
                )
                progressStat(
                    icon: "terminal",
                    label: "Commands",
                    value: "\(loop.commandsRun.count)"
                )
                progressStat(
                    icon: "checkmark.shield",
                    label: "Tests",
                    value: testSummary
                )
            }

            if !loop.filesChanged.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(loop.filesChanged, id: \.self) { file in
                        HStack(spacing: 6) {
                            Image(systemName: "doc")
                                .font(.system(size: 10))
                                .foregroundStyle(t.text3)
                            Text(file)
                                .font(.dsMonoPt(11))
                                .foregroundStyle(t.text2)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 4)
            }

            if !loop.commandsRun.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(loop.commandsRun, id: \.self) { cmd in
                        HStack(spacing: 6) {
                            Text("$")
                                .font(.dsMonoPt(11, weight: .medium))
                                .foregroundStyle(t.accent)
                            Text(cmd)
                                .font(.dsMonoPt(11))
                                .foregroundStyle(t.text2)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func progressStat(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(t.accent)
            Text(value)
                .font(.dsMonoPt(14, weight: .semibold))
                .foregroundStyle(t.text)
            Text(label)
                .font(.dsMonoPt(10))
                .foregroundStyle(t.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(t.surfaceSunk)
        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
    }

    private var testSummary: String {
        let passed = loop.testsRun.filter(\.passed).count
        let failed = loop.testsRun.filter { !$0.passed }.count
        if failed > 0 { return "\(passed)✓ \(failed)✗" }
        return "\(passed)✓"
    }

    // MARK: - Approvals

    private var approvalsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            DSListSectionHead("Approvals")
            HStack(spacing: 12) {
                approvalStat(label: "Asked", value: loop.approvalsAsked, tone: .warn)
                approvalStat(label: "Decided", value: loop.approvalsDecided, tone: .ok)
                approvalStat(label: "Policy exc.", value: loop.policyExceptions, tone: .danger)
            }
        }
    }

    private func approvalStat(label: String, value: Int, tone: DSChipTone) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.dsMonoPt(18, weight: .bold))
                .foregroundStyle(tone == .danger ? t.danger : t.text)
            Text(label)
                .font(.dsMonoPt(10))
                .foregroundStyle(t.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(t.surfaceSunk)
        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
    }

    // MARK: - Spend

    private var spendSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            DSListSectionHead("Spend")
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "$%.2f", loop.spendUSD))
                        .font(.dsMonoPt(20, weight: .bold))
                        .foregroundStyle(t.text)
                    Text("total spend")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                }

                Spacer()

                if let tokens = loop.tokenCount {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(tokens.inputTokens.formatted()) in")
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text2)
                        Text("\(tokens.outputTokens.formatted()) out")
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text2)
                    }
                }
            }
        }
    }

    // MARK: - Proof

    private func proofSection(_ proof: Loop.Proof) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DSListSectionHead("Final Proof")

            Text(proof.summary)
                .font(.dsSansPt(14))
                .foregroundStyle(t.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .background(t.surfaceSunk)
                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                        .strokeBorder(t.ok.opacity(0.3), lineWidth: 1)
                )

            if let diff = proof.diffSummary, !diff.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diff")
                        .font(.dsMonoPt(11, weight: .medium))
                        .foregroundStyle(t.text3)
                    Text(diff)
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text2)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let prURL = proof.prURL {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                        .foregroundStyle(t.accent)
                    Text(prURL)
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.accent)
                        .lineLimit(1)
                }
            }

            if !proof.testResults.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(proof.testResults, id: \.name) { result in
                        HStack(spacing: 6) {
                            Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(result.passed ? t.ok : t.danger)
                            Text(result.name)
                                .font(.dsMonoPt(11))
                                .foregroundStyle(t.text2)
                        }
                    }
                }
            }
        }
    }
}

/// Wrapper so a `UnifiedDiff` (Hashable, not Identifiable) can drive `.sheet(item:)`.
struct IdentifiableDiff: Identifiable {
    let id = UUID()
    let diff: UnifiedDiff
}

// MARK: - Ship It confirmation sheet

/// The decisive supervision action: stage + commit + push (+ open PR), gated by
/// a confirmation sheet showing the change summary and a prefilled commit message.
/// Mirrors the approval-decision flow (review → decide → ship). The ship RPC is
/// idempotent on the daemon, so a retry after a partial failure is safe.
struct ShipItSheet: View {
    let store: GitStore
    let loop: Loop
    let onOpenPR: (URL) -> Void

    @State private var message: String
    @State private var openPR = true
    @State private var result: GitShipResult?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    init(store: GitStore, loop: Loop, onOpenPR: @escaping (URL) -> Void) {
        self.store = store
        self.loop = loop
        self.onOpenPR = onOpenPR
        // Prefill the commit message from the loop's goal.
        _message = State(initialValue: loop.goal)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                t.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summary
                        commitField
                        Toggle("Open pull request", isOn: $openPR)
                            .font(.dsSansPt(13))
                            .tint(t.accent)
                        if let result {
                            resultView(result)
                        } else if let err = store.error, !err.isEmpty {
                            Text(err)
                                .font(.dsMonoPt(11))
                                .foregroundStyle(t.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        shipButton
                        Spacer(minLength: 0)
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Ship it")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let status = store.status {
                HStack(spacing: 6) {
                    DSChip(status.branch, systemImage: "arrow.triangle.branch", tone: .accent, variant: .outlined, size: .sm)
                    DSChip("\(status.changes.count) changed", tone: .warn, variant: .soft, size: .sm)
                }
            }
            if let repo = loop.repo {
                Text(repo).font(.dsMonoPt(11)).foregroundStyle(t.text3)
            }
        }
    }

    private var commitField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Commit message")
                .font(.dsMonoPt(11, weight: .medium))
                .foregroundStyle(t.text3)
            TextEditor(text: $message)
                .font(.dsMonoPt(13))
                .frame(minHeight: 80)
                .padding(8)
                .background(t.surfaceSunk)
                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        }
    }

    @ViewBuilder
    private func resultView(_ r: GitShipResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                DSChip(r.committed ? "committed ✓" : "not committed",
                       tone: r.committed ? .ok : .danger, variant: .soft, size: .sm)
                DSChip(r.pushed ? "pushed ✓" : "not pushed",
                       tone: r.pushed ? .ok : .warn, variant: .soft, size: .sm)
            }
            if let url = r.prURL, let parsed = URL(string: url) {
                DSButton("Open PR", variant: .secondary, size: .sm, mono: true) {
                    onOpenPR(parsed)
                }
            }
            if let msg = r.message, !msg.isEmpty {
                Text(msg)
                    .font(.dsMonoPt(10))
                    .foregroundStyle(r.isShipped ? t.warn : t.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var shipButton: some View {
        DSButton(result == nil ? "Ship it" : "Retry", variant: .primary, mono: true) {
            Task {
                result = await store.ship(
                    message: message,
                    openPR: openPR,
                    base: loop.branch == nil ? nil : "main",
                    title: message,
                    body: ""
                )
            }
        }
        .disabled(store.isShipping || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
#endif
