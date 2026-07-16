#if os(iOS)
import SwiftUI
import LancerCore

/// Thin host-policy editor over `agent.policy.get` / `agent.policy.set` (SSH
/// only — full per-rule YAML never round-trips over relay; see
/// docs/product/2026-07-16-policy-audit-relay-port-map.md). When no SSH
/// `DaemonChannel` is available (relay-only pairing), falls back to a coarse
/// permission-mode picker (deny/ask/allow) over `agentPermissionModeGet`/`Set`
/// instead of hiding the screen entirely.
public struct PolicyEditorView: View {
    private let cwd: String

    @Environment(RelayFleetStore.self) private var relayFleetStore
    @State private var policy: PolicyGetResult?
    @State private var yamlText = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    /// Determined at load time: SSH `DaemonChannel` present → full editor;
    /// otherwise (relay-only pairing) → coarse mode picker only.
    @State private var hasSSH = true
    @State private var permissionMode: PermissionMode?

    public init(cwd: String = "~") {
        self.cwd = cwd
    }

    public var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("cursor.settings.policy.error")
                }
            }
            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if hasSSH {
                fullEditorSections
            } else {
                relayOnlySections
            }
        }
        .navigationTitle("Policy")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .accessibilityIdentifier("cursor.settings.policy-editor")
    }

    @ViewBuilder
    private var fullEditorSections: some View {
        Section("Rules") {
            let rules = renderedRules
            if rules.isEmpty {
                Text(isLoading ? "Loading…" : "No rules in loaded documents.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ruleSummary(rule))
                            .font(.body.monospaced())
                        if let detail = ruleDetail(rule) {
                            Text(detail)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }

        Section {
            TextEditor(text: $yamlText)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 200)
                .accessibilityIdentifier("cursor.settings.policy.yaml")
        } header: {
            Text("YAML")
        } footer: {
            Text("Saves to the host global policy via agent.policy.set. Invalid YAML returns an error — success is never assumed.")
        }

        Section {
            Button {
                Task { await save() }
            } label: {
                if isSaving {
                    ProgressView()
                } else {
                    Text("Save policy")
                }
            }
            .disabled(isSaving || isLoading || yamlText.isEmpty)
            .accessibilityIdentifier("cursor.settings.policy.save")
        }
    }

    @ViewBuilder
    private var relayOnlySections: some View {
        Section {
            Picker("Default decision", selection: Binding(
                get: { permissionMode ?? .ask },
                set: { newMode in
                    permissionMode = newMode
                    Task { await setMode(newMode) }
                }
            )) {
                Text("Deny").tag(PermissionMode.deny)
                Text("Ask").tag(PermissionMode.ask)
                Text("Allow").tag(PermissionMode.allow)
            }
            .disabled(isSaving || isLoading)
            .accessibilityIdentifier("cursor.settings.policy.mode-picker")
        } header: {
            Text("Default decision")
        } footer: {
            Text("This relay-only connection can change the coarse default decision (deny / ask / allow), but full per-rule policy editing needs an SSH host session.")
                .accessibilityIdentifier("cursor.settings.policy.relay-only-footnote")
        }
    }

    private var renderedRules: [PolicyRule] {
        policy?.documents?.flatMap { $0.rules ?? [] } ?? []
    }

    private func ruleSummary(_ rule: PolicyRule) -> String {
        var parts = [rule.effect]
        if let kind = rule.kind, !kind.isEmpty { parts.append(kind) }
        if let tool = rule.tool, !tool.isEmpty { parts.append(tool) }
        if let id = rule.ruleID, !id.isEmpty { parts.append("#\(id)") }
        return parts.joined(separator: " · ")
    }

    private func ruleDetail(_ rule: PolicyRule) -> String? {
        var bits: [String] = []
        if let match = rule.match, !match.isEmpty { bits.append("match: \(match)") }
        if let agent = rule.agent, !agent.isEmpty { bits.append("agent: \(agent)") }
        if let minRisk = rule.minRisk { bits.append("minRisk: \(minRisk)") }
        if let maxRisk = rule.maxRisk { bits.append("maxRisk: \(maxRisk)") }
        if let cwd = rule.cwd, !cwd.isEmpty { bits.append("cwd: \(cwd)") }
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        defer { isLoading = false }
        do {
            let result = try await GovernanceHostActions.fetchPolicy(cwd: cwd)
            hasSSH = true
            policy = result
            if let yaml = result.yaml, !yaml.isEmpty {
                yamlText = yaml
            } else if yamlText.isEmpty {
                yamlText = ""
            }
        } catch GovernanceHostActions.Failure.sshRequired {
            // No SSH DaemonChannel — relay-only pairing. Fall back to the
            // coarse permission-mode picker rather than showing an error for a
            // perfectly normal connection type.
            hasSSH = false
            policy = nil
            await loadPermissionMode()
        } catch {
            policy = nil
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        errorMessage = nil
        statusMessage = nil
        defer { isSaving = false }
        do {
            try await GovernanceHostActions.savePolicyYAML(cwd: cwd, yaml: yamlText)
            statusMessage = "Saved."
            await load()
        } catch {
            // Fail-closed: never claim success on RPC error.
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    @MainActor
    private func loadPermissionMode() async {
        do {
            permissionMode = try await GovernanceHostActions.fetchPermissionMode(cwd: cwd, relayFleetStore: relayFleetStore)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func setMode(_ mode: PermissionMode) async {
        isSaving = true
        errorMessage = nil
        statusMessage = nil
        defer { isSaving = false }
        do {
            try await GovernanceHostActions.setPermissionMode(mode, cwd: cwd, relayFleetStore: relayFleetStore)
            statusMessage = "Saved."
        } catch {
            // Fail-closed: never claim success on RPC error; re-read the
            // actual current mode so the picker reflects reality, not the
            // rejected selection.
            errorMessage = error.localizedDescription
            statusMessage = nil
            await loadPermissionMode()
        }
    }
}
#endif
