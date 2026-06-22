#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit
import SettingsFeature
import DiffFeature
import DiffKit
import SSHTransport

struct AgentRunDetailView: View {
    @Bindable var store: AgentStore
    let run: AgentRun
    let agentID: String
    /// Git review/ship store for the agent's workspace. nil ⇒ Changes hidden.
    var gitStore: GitStore?

    @State private var showShipSheet = false
    @State private var diffToReview: RunDiff?
    /// PR shipped from this run (drives the ProofCard PR link + persists across redraws).
    @State private var shippedPRURL: String?

    @Environment(\.lancerTokens) private var t
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader("run", onBack: { dismiss() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        statusSection
                        if liveRun.status.isTerminal, let proofModel = buildProofModel() {
                            ProofCardView(model: proofModel, onPRTap: {
                                if let url = (shippedPRURL).flatMap(URL.init) { openURL(url) }
                            })
                        }
                        if gitStore != nil {
                            changesSection
                        }
                        logsSection
                        artifactsSection
                        if !run.approvals.isEmpty {
                            approvalsSection
                        }
                        if !displayUsageRecords.isEmpty {
                            usageSection
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationBarHidden(true)
        .task(id: run.id) {
            await store.loadArtifacts(runID: run.id)
            // Live tail: poll backend logs (cloud) + run status until terminal.
            while !Task.isCancelled {
                await store.loadNewRunLogs(runID: run.id)
                await store.refreshRun(run.id)
                if liveRun.status.isTerminal { break }
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .task(id: run.id) { await gitStore?.refresh() }
        .sheet(item: $diffToReview) { wrapped in
            NavigationStack { DiffView(diff: wrapped.diff) }
        }
        .sheet(isPresented: $showShipSheet) {
            if let gitStore {
                RunShipSheet(store: gitStore, defaultMessage: run.prompt ?? "Ship agent changes") { url in
                    shippedPRURL = url.absoluteString
                }
            }
        }
    }

    // MARK: - Changes (review + ship the agent's git work)

    @ViewBuilder
    private var changesSection: some View {
        if let git = gitStore {
            VStack(alignment: .leading, spacing: 8) {
                DSListSectionHead("CHANGES")
                if let status = git.status {
                    HStack(spacing: 8) {
                        DSChip(status.branch, systemImage: "arrow.triangle.branch", tone: .accent, variant: .outlined, size: .sm)
                        if status.ahead > 0 { DSChip("↑\(status.ahead)", tone: .info, variant: .soft, size: .sm) }
                        if status.behind > 0 { DSChip("↓\(status.behind)", tone: .warn, variant: .soft, size: .sm) }
                        DSChip(status.isClean ? "clean" : "\(status.changes.count) changed",
                               tone: status.isClean ? .ok : .warn, variant: .soft, size: .sm)
                        Spacer()
                    }
                }
                if !git.changedFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(git.changedFiles.prefix(8)) { file in
                            HStack(spacing: 6) {
                                Image(systemName: "doc").font(.system(size: 10)).foregroundStyle(t.text3)
                                Text(file.path).font(.dsMonoPt(11)).foregroundStyle(t.text2).lineLimit(1)
                                Spacer()
                                Text(file.status.rawValue).font(.dsMonoPt(9)).foregroundStyle(t.text3)
                            }
                        }
                        if git.changedFiles.count > 8 {
                            Text("+\(git.changedFiles.count - 8) more").font(.dsMonoPt(10)).foregroundStyle(t.text3)
                        }
                    }
                }
                if let err = git.error, !err.isEmpty {
                    Text(err).font(.dsMonoPt(10)).foregroundStyle(t.danger).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    DSButton("Review diff", variant: .secondary, size: .sm, mono: true) {
                        Task { if let d = await git.loadDiff() { diffToReview = RunDiff(diff: d) } }
                    }
                    DSButton("Ship it", variant: .primary, size: .sm, mono: true) { showShipSheet = true }
                        .disabled(git.isShipping)
                    Spacer()
                    if git.isLoading || git.isShipping { ProgressView().scaleEffect(0.7) }
                }
            }
        }
    }

    private var isLive: Bool { !liveRun.status.isTerminal }

    private var displayUsageRecords: [UsageRecord] {
        store.selectedRun?.usageRecords ?? run.usageRecords
    }

    private var liveRun: AgentRun {
        store.selectedRun?.id == run.id ? store.selectedRun! : run
    }

    private var statusSection: some View {
        let liveRun = liveRun
        let agent = store.agents.first { $0.id == agentID }
        return VStack(alignment: .leading, spacing: 8) {
            DSListSectionHead("STATUS")
            HStack(spacing: 8) {
                Text(liveRun.status.rawValue)
                    .font(.dsMonoPt(13, weight: .semibold))
                    .foregroundStyle(t.text)
                if let code = liveRun.exitCode {
                    DSChip("exit \(code)", tone: code == 0 ? .ok : .danger, variant: .soft, size: .sm)
                }
                Spacer()
            }
            if let endedAt = liveRun.endedAt {
                Text(endedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text4)
            }
            if agent?.runtimeKind == .sshHost && !liveRun.status.isTerminal {
                DSButton("Cancel run", variant: .destructive, size: .sm, mono: true) {
                    Task { if let agent { await store.cancelRun(runID: run.id, agent: agent) } }
                }
            }
        }
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DSListSectionHead("LOGS")
                Spacer()
                if isLive {
                    HStack(spacing: 4) {
                        Circle().fill(t.ok).frame(width: 6, height: 6)
                        Text("live")
                            .font(.dsMonoPt(10, weight: .semibold))
                            .foregroundStyle(t.ok)
                    }
                }
            }
            let lines = store.logLines(for: run.id, fallback: run)
            if lines.isEmpty {
                Text("No log lines yet.")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text3)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(lines) { line in
                                Text(line.text)
                                    .font(.dsMonoPt(12))
                                    .foregroundStyle(t.text2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(line.id)
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                    .onChange(of: lines.count) { _, _ in
                        if let last = lines.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }
        }
    }

    private var artifactsSection: some View {
        let agent = store.agents.first { $0.id == agentID }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                DSListSectionHead("ARTIFACTS")
                Spacer()
                if let agent, agent.runtimeKind == .sshHost {
                    NavigationLink {
                        AgentFilesView(store: store, agent: agent, attachToRunID: run.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "paperclip")
                            Text("Attach from host")
                        }
                        .font(.dsMonoPt(11, weight: .semibold))
                        .foregroundStyle(t.accent)
                    }
                }
            }
            let artifacts = store.artifactsByRun[run.id] ?? []
            if artifacts.isEmpty {
                Text("No artifacts for this run.")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text3)
            } else {
                ForEach(artifacts) { artifact in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(artifact.name)
                                .font(.dsMonoPt(13, weight: .semibold))
                                .foregroundStyle(t.text)
                            if let bytes = artifact.sizeBytes {
                                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                                    .font(.dsMonoPt(10))
                                    .foregroundStyle(t.text4)
                            }
                        }
                        Spacer()
                        if let gcsURI = artifact.gcsURI, !gcsURI.isEmpty {
                            // Cloud artifact: fetch a short-lived signed URL from the backend.
                            DSButton("Download", variant: .ghost, size: .sm, mono: true) {
                                Task {
                                    if let url = await store.artifactDownloadURL(runID: run.id, artifactID: artifact.id) {
                                        openURL(url)
                                    }
                                }
                            }
                        } else if artifact.downloadURL != nil {
                            DSButton("Open", variant: .ghost, size: .sm, mono: true) {
                                if let url = artifact.downloadURL { openURL(url) }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var approvalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSListSectionHead("APPROVALS")
            let approvals = store.selectedRun?.approvals ?? run.approvals
            ForEach(approvals) { approval in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(approval.kind)
                            .font(.dsMonoPt(13, weight: .semibold))
                            .foregroundStyle(t.text)
                        if let cmd = approval.command {
                            Text(cmd)
                                .font(.dsMonoPt(11))
                                .foregroundStyle(t.text3)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    if approval.status == .pending {
                        HStack(spacing: 8) {
                            DSButton("Deny", variant: .secondary, mono: true) {
                                Task { await store.respondToApproval(runID: run.id, approvalID: approval.id, approved: false) }
                            }
                            DSButton("Allow", variant: .primary, mono: true) {
                                Task { await store.respondToApproval(runID: run.id, approvalID: approval.id, approved: true) }
                            }
                        }
                    } else {
                        DSChip(approval.status.rawValue, tone: approval.status == .approved ? .ok : .danger, variant: .soft)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSListSectionHead("USAGE")
            ForEach(displayUsageRecords) { record in
                HStack {
                    Text(record.model ?? "model")
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text2)
                    Spacer()
                    Text("\(record.inputTokens) in / \(record.outputTokens) out")
                        .font(.dsMonoPt(10))
                        .foregroundStyle(t.text4)
                    if let cost = record.costUSD {
                        Text(String(format: "$%.4f", cost))
                            .font(.dsMonoPt(12))
                            .foregroundStyle(t.text3)
                    }
                }
            }
        }
    }

    private func buildProofModel() -> ProofCardModel? {
        let agent = store.agents.first { $0.id == agentID }
        let agentKey: AgentKey = {
            switch agent?.runtimeKind {
            case .sshHost: return .claudeCode
            case .fly, .gcpCloudRun, .lightsail: return .codex
            case .none:    return .unknown
            }
        }()
        let agentName = agent?.name ?? "Agent"

        let status: ProofCardModel.Status = {
            switch liveRun.status {
            case .succeeded: return .completed
            case .failed:    return .failed
            case .cancelled: return .cancelled
            default:         return .completed
            }
        }()

        var duration: String?
        let end = liveRun.endedAt ?? Date()
        let secs = Int(end.timeIntervalSince(liveRun.startedAt))
        if secs >= 60 {
            duration = "\(secs / 60)m \(secs % 60)s"
        } else {
            duration = "\(secs)s"
        }

        let approvals = store.selectedRun?.approvals ?? run.approvals
        let approved = approvals.filter { $0.status == .approved }.count
        let denied = approvals.filter { $0.status == .rejected }.count
        let approvalSummary = approvals.isEmpty ? nil : ProofCardModel.ApprovalSummary(
            asked: approvals.count,
            approved: approved,
            denied: denied
        )

        let totalCost = displayUsageRecords.compactMap(\.costUSD).reduce(0, +)
        let totalInput = displayUsageRecords.map(\.inputTokens).reduce(0, +)
        let totalOutput = displayUsageRecords.map(\.outputTokens).reduce(0, +)
        let spend: ProofCardModel.SpendSummary? = totalCost > 0 ? ProofCardModel.SpendSummary(
            totalUSD: totalCost,
            inputTokens: totalInput,
            outputTokens: totalOutput
        ) : nil

        // Surface the diff summary + shipped PR link in the run's terminal artifact.
        let diffSummary: ProofCardModel.DiffSummary? = {
            let files = gitStore?.changedFiles ?? []
            guard !files.isEmpty else { return nil }
            return ProofCardModel.DiffSummary(
                filesChanged: files.count,
                insertions: 0,
                deletions: 0,
                fileNames: files.map(\.path)
            )
        }()

        let prNumber = shippedPRURL.flatMap(Self.prNumber(fromURL:))

        return ProofCardModel(
            agent: agentKey,
            agentName: agentName,
            status: status,
            duration: duration,
            tests: nil,
            diff: diffSummary,
            commands: [],
            approvals: approvalSummary,
            policyExceptions: 0,
            spend: spend,
            prURL: shippedPRURL,
            prNumber: prNumber
        )
    }

    /// Extract the PR number from a GitHub PR URL (…/pull/123) for the card label.
    private static func prNumber(fromURL url: String) -> Int? {
        guard let range = url.range(of: "/pull/") else { return nil }
        let tail = url[range.upperBound...].prefix { $0.isNumber }
        return Int(tail)
    }
}

/// Wrapper so a `UnifiedDiff` can drive `.sheet(item:)` in the run detail.
private struct RunDiff: Identifiable {
    let id = UUID()
    let diff: UnifiedDiff
}

/// "Ship it" confirmation sheet for a run — stage + commit + push (+ PR), gated
/// by a prefilled commit message. Idempotent ship RPC ⇒ safe retry.
private struct RunShipSheet: View {
    let store: GitStore
    let defaultMessage: String
    let onOpenPR: (URL) -> Void

    @State private var message: String
    @State private var openPR = true
    @State private var result: GitShipResult?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.lancerTokens) private var t

    init(store: GitStore, defaultMessage: String, onOpenPR: @escaping (URL) -> Void) {
        self.store = store
        self.defaultMessage = defaultMessage
        self.onOpenPR = onOpenPR
        _message = State(initialValue: defaultMessage)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                t.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let status = store.status {
                            HStack(spacing: 6) {
                                DSChip(status.branch, systemImage: "arrow.triangle.branch", tone: .accent, variant: .outlined, size: .sm)
                                DSChip("\(status.changes.count) changed", tone: .warn, variant: .soft, size: .sm)
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Commit message").font(.dsMonoPt(11, weight: .medium)).foregroundStyle(t.text3)
                            TextEditor(text: $message)
                                .font(.dsMonoPt(13))
                                .frame(minHeight: 80)
                                .padding(8)
                                .background(t.surfaceSunk)
                                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                        }
                        Toggle("Open pull request", isOn: $openPR).font(.dsSansPt(13)).tint(t.accent)
                        if let r = result {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    DSChip(r.committed ? "committed ✓" : "not committed",
                                           tone: r.committed ? .ok : .danger, variant: .soft, size: .sm)
                                    DSChip(r.pushed ? "pushed ✓" : "not pushed",
                                           tone: r.pushed ? .ok : .warn, variant: .soft, size: .sm)
                                }
                                if let url = r.prURL, let parsed = URL(string: url) {
                                    DSButton("Open PR", variant: .secondary, size: .sm, mono: true) { onOpenPR(parsed) }
                                }
                                if let msg = r.message, !msg.isEmpty {
                                    Text(msg).font(.dsMonoPt(10))
                                        .foregroundStyle(r.isShipped ? t.warn : t.danger)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        } else if let err = store.error, !err.isEmpty {
                            Text(err).font(.dsMonoPt(11)).foregroundStyle(t.danger).fixedSize(horizontal: false, vertical: true)
                        }
                        DSButton(result == nil ? "Ship it" : "Retry", variant: .primary, mono: true) {
                            Task {
                                let r = await store.ship(message: message, openPR: openPR, base: "main", title: message, body: "")
                                result = r
                                if let url = r?.prURL, let parsed = URL(string: url) { onOpenPR(parsed) }
                            }
                        }
                        .disabled(store.isShipping || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer(minLength: 0)
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Ship it")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}
#endif
