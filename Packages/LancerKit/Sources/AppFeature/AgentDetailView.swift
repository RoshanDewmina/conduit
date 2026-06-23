#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit
import SettingsFeature
import SSHTransport

// MARK: - Agent detail + run history

struct AgentDetailView: View {
    @Bindable var store: AgentStore
    let agent: HostedAgent
    var gitChannel: DaemonChannel? = nil

    @State private var prompt = ""
    @State private var isRunning = false
    @State private var schedulePreset: SchedulePreset = .daily
    @State private var scheduleCommand = ""
    @State private var scheduleSaving = false
    @State private var editingSchedule: AgentSchedule?
    @State private var deletingSchedule: AgentSchedule?
    @State private var showAPIKey = false
    @State private var isDefaultAgent = true
    @State private var selectedModelID: String?
    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss

    private var effectiveModelID: String {
        selectedModelID ?? (agent.model.isEmpty ? "claude-opus-4-8" : agent.model)
    }

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                navBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        apiKeySection
                        modelPickerSection
                        defaultAgentToggle
                        usageSummarySection
                        Divider().background(t.divider).padding(.vertical, 4)
                        runPromptSection
                        scheduleSection
                        toolsSection
                        if store.teamOrg != nil {
                            teamSection
                        }
                        runHistorySection
                    }
                    .padding(22)
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

    // MARK: - Nav bar

    private var navBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.text)
                    .frame(width: 36, height: 36)
                    .background(t.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                            .strokeBorder(t.border, lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(agent.name)
                .font(.dsSansPt(17, weight: .semibold))
                .foregroundStyle(t.text)
            Spacer()
            // Placeholder for symmetry
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 22)
        .padding(.top, 60)
    }

    // MARK: - API Key

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("API key")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)
            HStack {
                if showAPIKey {
                    Text("sk-ant-api03-••••••••")
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text4)
                } else {
                    Text("••••••••••••••••")
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text4)
                        .tracking(2)
                }
                Spacer()
                Button {
                    showAPIKey.toggle()
                } label: {
                    Text(showAPIKey ? "hide" : "show")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1))
        }
    }

    // MARK: - Model picker

    private var modelPickerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Model")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)
            VStack(spacing: 4) {
                ForEach(ModelCatalog.models(for: "claudeCode"), id: \.id) { model in
                    modelOption(
                        model.id,
                        subtitle: model.id == "claude-opus-4-8" ? "Recommended" : nil,
                        isSelected: model.id == effectiveModelID
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selectedModelID = model.id }
                }
            }
        }
    }

    @ViewBuilder
    private func modelOption(_ name: String, subtitle: String?, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .strokeBorder(isSelected ? t.accent : t.text4, lineWidth: 1.5)
                    .frame(width: 10, height: 10)
                if isSelected {
                    Circle()
                        .fill(t.accent)
                        .frame(width: 6, height: 6)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.dsMonoPt(9.5))
                        .foregroundStyle(t.text4)
                }
            }
            Spacer()
        }
        .padding(10)
        .padding(.horizontal, 2)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                .strokeBorder(isSelected ? t.accent : t.border, lineWidth: isSelected ? 1.5 : 1))
    }

    // MARK: - Default agent toggle

    private var defaultAgentToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Default agent")
                    .font(.dsMonoPt(11.5))
                    .foregroundStyle(t.text)
                Text("Fallback for new sessions")
                    .font(.dsMonoPt(9.5))
                    .foregroundStyle(t.text4)
            }
            Spacer()
            Toggle("", isOn: $isDefaultAgent)
                .tint(t.accent)
                .labelsHidden()
                .frame(width: 44)
        }
        .padding(12)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1))
    }

    // MARK: - Usage summary

    private var usageSummarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("USAGE THIS MONTH")
                .font(.dsMonoPt(10))
                .tracking(10 * 0.05)
                .foregroundStyle(t.text4)
            HStack(spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("847K")
                        .font(.dsMonoPt(13, weight: .semibold))
                        .foregroundStyle(t.text)
                    Text("tokens in")
                        .font(.dsMonoPt(9.5))
                        .foregroundStyle(t.text4)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("2.3M")
                        .font(.dsMonoPt(13, weight: .semibold))
                        .foregroundStyle(t.text)
                    Text("tokens out")
                        .font(.dsMonoPt(9.5))
                        .foregroundStyle(t.text4)
                }
                Spacer()
            }
        }
        .padding(12)
        .background(t.surfaceSunk)
        .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1))
    }

    // MARK: - Run prompt

    private var runPromptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RUN")
                .font(.dsMonoPt(11, weight: .semibold))
                .tracking(11 * 0.1)
                .textCase(.uppercase)
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
                .background(t.surface, in: RoundedRectangle(cornerRadius: t.r2))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r2)
                        .strokeBorder(t.border, lineWidth: 1))
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

    // MARK: - Schedule

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
                .background(t.surface, in: RoundedRectangle(cornerRadius: t.r2))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r2)
                        .strokeBorder(t.border, lineWidth: 1))
            DSButton(scheduleSaving ? "Saving…" : "Save schedule", variant: .secondary, mono: true) {
                Task {
                    scheduleSaving = true
                    defer { scheduleSaving = false }
                    try? await store.saveSchedule(
                        agentID: agent.id,
                        cronExpr: schedulePreset.rawValue,
                        command: scheduleCommand.isEmpty ? agent.command ?? "" : scheduleCommand
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

    // MARK: - Tools

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

    // MARK: - Team

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

    // MARK: - Run history

    private func makeGitStore() -> GitStore? {
        guard agent.runtimeKind == .sshHost,
              let workdir = agent.workspacePath, !workdir.isEmpty,
              let gitChannel else { return nil }
        return GitStore(channel: gitChannel, workdir: workdir)
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
                        AgentRunDetailView(store: store, run: run, agentID: agent.id, gitStore: makeGitStore())
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
