#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit
import SettingsFeature

public struct AgentsView: View {
    @Bindable var store: AgentStore
    @State private var pm = PurchaseManager.shared
    @State private var showingCreate = false
    @State private var selectedAgent: HostedAgent?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    public init(store: AgentStore) {
        self.store = store
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader("agents", onBack: { dismiss() }) {
                    if store.hasCloudEntitlement {
                        DSIconButton(.plus) { showingCreate = true }
                    }
                }

                if !store.hasCloudEntitlement {
                    cloudGate
                } else if store.isLoading {
                    DSSkeletonList(count: 3, showAvatar: true)
                    Spacer()
                } else if store.agents.isEmpty {
                    Spacer()
                    DSEmptyState(
                        icon: .sparkles,
                        title: "no agents",
                        subtitle: "Create a hosted agent to run claude or codex on your SSH host."
                    )
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.agents) { agent in
                                NavigationLink {
                                    AgentDetailView(store: store, agent: agent)
                                } label: {
                                    agentRow(agent)
                                }
                                .buttonStyle(.plain)
                                DSDivider()
                            }
                        }
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await pm.refreshCloudEntitlement()
            await store.loadAgents()
        }
        .sheet(isPresented: $showingCreate) {
            CreateAgentSheet(store: store)
        }
    }

    private var cloudGate: some View {
        VStack(spacing: 16) {
            Spacer()
            DSEmptyState(
                icon: .sparkles,
                title: "Conduit Cloud required",
                subtitle: "Hosted agents need an active Conduit Cloud subscription. Manage billing in Settings."
            )
            if pm.externalStripeEligible {
                Link(destination: URL(string: "https://conduit.dev/subscribe")!) {
                    Text("Subscribe at conduit.dev")
                        .font(.dsSansPt(14, weight: .semibold))
                        .foregroundStyle(t.accent)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func agentRow(_ agent: HostedAgent) -> some View {
        HStack(spacing: 12) {
            PixelAvatar(seed: agent.name, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(agent.name)
                    .font(.dsMonoPt(14, weight: .semibold))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                Text(agent.model)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                DSStatusDot(tone: agent.isActive ? .ok : .off, pulse: agent.isActive)
                Text(store.monthlyCostLabel(for: agent))
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text4)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Agent detail + run history

struct AgentDetailView: View {
    @Bindable var store: AgentStore
    let agent: HostedAgent

    @State private var prompt = ""
    @State private var isRunning = false
    @Environment(\.conduitTokens) private var t

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader(agent.name)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        runPromptSection
                        runHistorySection
                    }
                    .padding(16)
                }
            }
        }
        .navigationBarHidden(true)
        .task { await store.loadRuns(for: agent.id) }
    }

    private var runPromptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RUN")
                .font(.dsMonoPt(11, weight: .semibold))
                .foregroundStyle(t.text3)
            TextField("Prompt or task…", text: $prompt, axis: .vertical)
                .font(.dsMonoPt(14))
                .lineLimit(3...6)
                .padding(12)
                .background(t.surface, in: RoundedRectangle(cornerRadius: t.radiusMD))
            DSButton(isRunning ? "Running…" : "Start run", variant: .primary, mono: true) {
                Task {
                    isRunning = true
                    defer { isRunning = false }
                    _ = try? await store.startRun(agent: agent, prompt: prompt.isEmpty ? nil : prompt)
                    await store.loadRuns(for: agent.id)
                }
            }
            .disabled(isRunning)
        }
    }

    private var runHistorySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSListSectionHead("RUN HISTORY")
            let runs = store.runsByAgent[agent.id] ?? []
            if runs.isEmpty {
                Text("No runs yet.")
                    .font(.dsMonoPt(13))
                    .foregroundStyle(t.text3)
                    .padding(.vertical, 12)
            } else {
                ForEach(runs) { run in
                    NavigationLink {
                        AgentRunDetailView(store: store, run: run)
                    } label: {
                        runRow(run)
                    }
                    .buttonStyle(.plain)
                    DSDivider()
                }
            }
        }
    }

    private func runRow(_ run: AgentRun) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(run.status.rawValue)
                    .font(.dsMonoPt(13, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(t.text4)
        }
        .padding(.vertical, 12)
    }
}

struct AgentRunDetailView: View {
    @Bindable var store: AgentStore
    let run: AgentRun

    @Environment(\.conduitTokens) private var t

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader("run")
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        logsSection
                        if !run.approvals.isEmpty {
                            approvalsSection
                        }
                        if !run.usageRecords.isEmpty {
                            usageSection
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationBarHidden(true)
        .task { await store.refreshRun(run.id) }
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSListSectionHead("LOGS")
            let lines = store.selectedRun?.logLines ?? run.logLines
            ForEach(lines) { line in
                Text(line.text)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            let records = store.selectedRun?.usageRecords ?? run.usageRecords
            ForEach(records) { record in
                HStack {
                    Text(record.model ?? "model")
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text2)
                    Spacer()
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

struct CreateAgentSheet: View {
    @Bindable var store: AgentStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    @State private var name = ""
    @State private var model = "anthropic/claude-sonnet-4"
    @State private var hostID = ""
    @State private var command = "claude"
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Agent") {
                    TextField("Name", text: $name)
                    TextField("Model", text: $model)
                    TextField("Host ID", text: $hostID)
                    TextField("Command", text: $command)
                }
                if let error {
                    Text(error)
                        .foregroundStyle(t.danger)
                }
            }
            .navigationTitle("New Agent")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            do {
                                _ = try await store.createAgent(
                                    name: name,
                                    model: model,
                                    hostID: hostID,
                                    command: command
                                )
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                    .disabled(name.isEmpty || hostID.isEmpty)
                }
            }
        }
    }
}
#endif
