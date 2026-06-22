#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit
import SettingsFeature

struct CreateAgentSheet: View {
    @Bindable var store: AgentStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lancerTokens) private var t

    @State private var name = ""
    @State private var model = ManagedModel.default.rawValue
    @State private var useCustomModel = false
    @State private var runtimeChoice: HostedRuntimeChoice = .sshHost
    @State private var hostID = ""
    @State private var command = "claude"
    @State private var workspacePath = ""
    @State private var region = CloudRegion.default.slug
    @State private var error: String?

    /// Concrete backend runtime kind derived from the user-facing choice.
    private var runtimeKind: HostedRuntimeKind { runtimeChoice.runtimeKind }

    private static let customModelTag = "__custom__"

    /// Drives the model Picker: reflects the curated slug, or the custom sentinel
    /// when a non-preset slug is in play. Writing the sentinel reveals the text field.
    private var modelSelection: Binding<String> {
        Binding(
            get: { useCustomModel || ManagedModel.isCustom(model) ? Self.customModelTag : model },
            set: { newValue in
                if newValue == Self.customModelTag {
                    useCustomModel = true
                } else {
                    useCustomModel = false
                    model = newValue
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Agent") {
                    TextField("Name", text: $name)
                    Picker("Model", selection: modelSelection) {
                        ForEach(ManagedModel.allCases, id: \.self) { managed in
                            Text(managed.label).tag(managed.rawValue)
                        }
                        Text("Custom…").tag(Self.customModelTag)
                    }
                    if useCustomModel {
                        TextField("Model slug", text: $model)
                    }
                    Picker("Run on", selection: $runtimeChoice) {
                        ForEach(HostedRuntimeChoice.allCases, id: \.self) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(runtimeChoice.subtitle)
                        .font(.caption)
                        .foregroundStyle(t.text3)
                    if runtimeChoice == .sshHost {
                        TextField("Host ID", text: $hostID)
                    }
                    TextField("Command", text: $command)
                }
                if runtimeChoice == .cloud {
                    Section("Cloud region") {
                        Picker("Region", selection: $region) {
                            ForEach(CloudRegion.catalog) { r in
                                Text(r.displayName).tag(r.slug)
                            }
                        }
                    }
                }
                if runtimeChoice == .sshHost {
                    Section("Workspace (optional)") {
                        TextField("Repo path on host, e.g. ~/projects/app", text: $workspacePath)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
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
                                    runtimeKind: runtimeKind,
                                    hostID: hostID,
                                    command: command,
                                    workspacePath: workspacePath,
                                    region: region
                                )
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                    .disabled(name.isEmpty || (runtimeChoice == .sshHost && hostID.isEmpty))
                }
            }
        }
    }
}
#endif
