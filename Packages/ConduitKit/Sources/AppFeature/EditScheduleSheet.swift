#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit
import SettingsFeature

/// Edits an existing schedule: interval (preset or custom cron), command, and
/// enabled state. Maps onto `PATCH /schedules/{id}` via `store.updateSchedule`.
struct EditScheduleSheet: View {
    @Bindable var store: AgentStore
    let agentID: String
    let schedule: AgentSchedule

    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    @State private var cronExpr: String
    @State private var command: String
    @State private var enabled: Bool
    @State private var useCustom: Bool
    @State private var saving = false
    @State private var error: String?

    private static let customTag = "__custom__"

    init(store: AgentStore, agentID: String, schedule: AgentSchedule) {
        self.store = store
        self.agentID = agentID
        self.schedule = schedule
        _cronExpr = State(initialValue: schedule.cronExpr)
        _command = State(initialValue: schedule.command ?? "")
        _enabled = State(initialValue: schedule.enabled)
        _useCustom = State(initialValue: SchedulePreset(rawValue: schedule.cronExpr) == nil)
    }

    /// Drives the interval Picker: a preset rawValue, or the custom sentinel.
    private var presetSelection: Binding<String> {
        Binding(
            get: { useCustom ? Self.customTag : cronExpr },
            set: { newValue in
                if newValue == Self.customTag {
                    useCustom = true
                } else {
                    useCustom = false
                    cronExpr = newValue
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Interval") {
                    Picker("Interval", selection: presetSelection) {
                        ForEach(SchedulePreset.allCases, id: \.self) { preset in
                            Text(preset.label).tag(preset.rawValue)
                        }
                        Text("Custom…").tag(Self.customTag)
                    }
                    if useCustom {
                        TextField("Cron (e.g. every:3600)", text: $cronExpr)
                            .font(.dsMonoPt(13))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                        Text("@hourly, @daily, @weekly, or every:<seconds>")
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text4)
                    }
                }
                Section("Command") {
                    TextField("Command (optional)", text: $command)
                        .font(.dsMonoPt(13))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
                Section {
                    Toggle("Enabled", isOn: $enabled)
                }
                if let error {
                    Text(error).foregroundStyle(t.danger)
                }
            }
            .navigationTitle("Edit Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { save() }
                        .disabled(saving || cronExpr.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        saving = true
        error = nil
        Task {
            defer { saving = false }
            do {
                try await store.updateSchedule(
                    scheduleID: schedule.id,
                    agentID: agentID,
                    cronExpr: cronExpr.trimmingCharacters(in: .whitespaces),
                    command: command,
                    enabled: enabled
                )
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
#endif
