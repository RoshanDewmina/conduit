#if os(iOS)
import SwiftUI
import LancerCore

/// Thin host-policy editor over `agent.policy.get` / `agent.policy.set`.
/// Read-only rendered rules + raw YAML with save; validation errors come from the RPC.
public struct PolicyEditorView: View {
    private let cwd: String

    @State private var policy: PolicyGetResult?
    @State private var yamlText = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

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
        .navigationTitle("Policy")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .accessibilityIdentifier("cursor.settings.policy-editor")
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
            policy = result
            if let yaml = result.yaml, !yaml.isEmpty {
                yamlText = yaml
            } else if yamlText.isEmpty {
                yamlText = ""
            }
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
}
#endif
