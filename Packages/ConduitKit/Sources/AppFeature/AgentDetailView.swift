#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit
import SettingsFeature

// MARK: - Agent detail + run history

struct AgentDetailView: View {
    @Bindable var store: AgentStore
    let agent: HostedAgent

    @State private var prompt = ""
    @State private var isRunning = false
    @State private var schedulePreset: SchedulePreset = .daily
    @State private var scheduleCommand = ""
    @State private var scheduleSaving = false
    @State private var editingSchedule: AgentSchedule?
    @State private var deletingSchedule: AgentSchedule?
    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader(agent.name, onBack: { dismiss() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        runPromptSection
                        scheduleSection
                        toolsSection
                        if store.teamOrg != nil {
                            teamSection
                        }
                        runHistorySection
                    }
                    .padding(16)
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await store.loadRuns(for: agent.id)
            await store.loadSchedules(agentID: agent.id)
        }
        .sheet(item: $editingSchedule) { schedule in
            EditScheduleSheet(store: store, agentID: agent.id, schedule: schedule)
        }
        .confirmationDialog(
            "Delete this schedule?",
            isPresented: Binding(
                get: { deletingSchedule != nil },
                set: { if !$0 { deletingSchedule = nil } }
            ),
            presenting: deletingSchedule
        ) { schedule in
            Button("Delete", role: .destructive) {
                Task {
                    try? await store.deleteSchedule(scheduleID: schedule.id, agentID: agent.id)
                    deletingSchedule = nil
                }
            }
            Button("Cancel", role: .cancel) { deletingSchedule = nil }
        }
    }

    private var runPromptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RUN")
                .font(.dsMonoPt(11, weight: .semibold))
                .foregroundStyle(t.text3)
            if agent.runtimeKind.isCloud {
                Text("Runs in a managed cloud sandbox\(agent.region.map { " · \($0)" } ?? "") via the control plane.")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            } else if !agent.runtimeKind.requiresHostID {
                Text("Runs execute on \(agent.runtimeKind.displayName) via the control plane.")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }
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
                    await store.loadBillingSnapshot()
                }
            }
            .disabled(isRunning)
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSListSectionHead("SCHEDULE")
            Picker("Interval", selection: $schedulePreset) {
                ForEach(SchedulePreset.allCases, id: \.self) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            TextField("Command (optional)", text: $scheduleCommand)
                .font(.dsMonoPt(13))
                .padding(10)
                .background(t.surface, in: RoundedRectangle(cornerRadius: t.radiusMD))
            DSButton(scheduleSaving ? "Saving…" : "Save schedule", variant: .secondary, mono: true) {
                Task {
                    scheduleSaving = true
                    defer { scheduleSaving = false }
                    try? await store.saveSchedule(
                        agentID: agent.id,
                        cronExpr: schedulePreset.rawValue,
                        command: scheduleCommand.isEmpty ? agent.command : scheduleCommand
                    )
                }
            }
            .disabled(scheduleSaving)

            let schedules = store.schedulesByAgent[agent.id] ?? []
            if schedules.isEmpty {
                Text("No schedules yet.")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text3)
            } else {
                ForEach(schedules) { schedule in
                    scheduleRow(schedule)
                }
            }
        }
    }

    @ViewBuilder
    private func scheduleRow(_ schedule: AgentSchedule) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(schedule.cronExpr)
                    .font(.dsMonoPt(12, weight: .semibold))
                    .foregroundStyle(t.text)
                if let runLine = scheduleRunLine(schedule) {
                    Text(runLine)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    Task {
                        try? await store.toggleSchedule(
                            scheduleID: schedule.id,
                            agentID: agent.id,
                            enabled: !schedule.enabled
                        )
                    }
                } label: {
                    DSChip(schedule.enabled ? "on" : "off", tone: schedule.enabled ? .ok : .neutral, variant: .soft, size: .sm)
                }
                .buttonStyle(.plain)
                DSButton("Run now", variant: .ghost, size: .sm, mono: true) {
                    Task { try? await store.triggerSchedule(scheduleID: schedule.id, agentID: agent.id) }
                }
                Menu {
                    Button("Edit") { editingSchedule = schedule }
                    Button("Delete", role: .destructive) { deletingSchedule = schedule }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(t.text3)
                        .frame(width: 28, height: 28)
                }
            }
        }
    }

    private func scheduleRunLine(_ schedule: AgentSchedule) -> String? {
        var parts: [String] = []
        if let next = schedule.nextRunAt {
            parts.append("next \(next.formatted(date: .abbreviated, time: .shortened))")
        }
        if let last = schedule.lastRunAt {
            parts.append("last \(last.formatted(date: .abbreviated, time: .shortened))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSListSectionHead("TOOLS")
            if agent.runtimeKind == .sshHost {
                toolRow("Exec console", systemImage: "terminal") {
                    AgentExecView(store: store, agent: agent)
                }
                toolRow("Files", systemImage: "folder") {
                    AgentFilesView(store: store, agent: agent)
                }
                if agent.workspacePath != nil {
                    toolRow("Workspace", systemImage: "arrow.triangle.branch") {
                        AgentWorkspaceView(store: store, agent: agent)
                    }
                }
            } else {
                Text("Interactive tools require an ssh-host runtime.")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text3)
                    .padding(.vertical, 12)
            }
        }
    }

    private func toolRow<Destination: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.accent)
                    .frame(width: 18)
                Text(title)
                    .font(.dsMonoPt(13, weight: .semibold))
                    .foregroundStyle(t.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(t.text4)
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private var teamSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSListSectionHead("TEAM")
            NavigationLink {
                AgentOrgView(store: store)
            } label: {
                HStack {
                    Text(store.teamOrg?.displayName ?? "Team")
                        .font(.dsMonoPt(13, weight: .semibold))
                        .foregroundStyle(t.text)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(t.text4)
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
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
                        AgentRunDetailView(store: store, run: run, agentID: agent.id)
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
#endif
