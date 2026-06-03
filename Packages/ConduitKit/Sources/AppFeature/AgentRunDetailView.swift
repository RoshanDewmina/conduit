#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit
import SettingsFeature

struct AgentRunDetailView: View {
    @Bindable var store: AgentStore
    let run: AgentRun
    let agentID: String

    @Environment(\.conduitTokens) private var t
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
        .task {
            await store.refreshRun(run.id)
            await store.loadArtifacts(runID: run.id)
        }
    }

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
            DSListSectionHead("LOGS")
            let lines = store.selectedRun?.logLines ?? run.logLines
            if lines.isEmpty {
                Text("No log lines yet.")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text3)
            } else {
                ForEach(lines) { line in
                    Text(line.text)
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var artifactsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSListSectionHead("ARTIFACTS")
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
                        if artifact.downloadURL != nil {
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
}
#endif
