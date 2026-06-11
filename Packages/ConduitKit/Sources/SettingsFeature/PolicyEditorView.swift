#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem

/// View/edit remote policy YAML via daemon RPC (presets + raw editor).
public struct PolicyEditorView: View {
    @State private var yamlText: String
    @State private var statusMessage: String?
    @State private var isSaving = false
    private let cwd: String
    private let onReload: () async -> Void
    private let onSave: ((String) async throws -> Void)?

    @Environment(\.conduitTokens) private var t

    public init(
        cwd: String,
        initialYAML: String,
        onReload: @escaping () async -> Void,
        onSave: ((String) async throws -> Void)? = nil
    ) {
        self.cwd = cwd
        _yamlText = State(initialValue: initialYAML)
        self.onReload = onReload
        self.onSave = onSave
    }

    public var body: some View {
        Form {
            Section("Safe presets") {
                Button("Strict (deny network & secrets)") { yamlText = Self.strictPreset }
                Button("Balanced (fail-closed ask)") { yamlText = Self.balancedPreset }
                Button("Permissive reads") { yamlText = Self.permissivePreset }
            }
            Section("Policy YAML") {
                Text("Edit on the bridge host at ~/.conduit/policy.yaml — reload after external edits.")
                    .font(.caption)
                    .foregroundStyle(t.text3)
                TextEditor(text: $yamlText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 220)
            }
            Section {
                Button("Reload policy on bridge") {
                    Task {
                        await onReload()
                        statusMessage = "Reloaded on bridge."
                    }
                }
                if let onSave {
                    Button(isSaving ? "Saving…" : "Save to bridge") {
                        Task {
                            isSaving = true
                            defer { isSaving = false }
                            do {
                                try await onSave(yamlText)
                                statusMessage = "Saved to bridge."
                            } catch {
                                statusMessage = error.localizedDescription
                            }
                        }
                    }
                    .disabled(isSaving)
                } else {
                    Text("Connect an SSH session to edit policy on the bridge.")
                        .font(.caption)
                        .foregroundStyle(t.text3)
                }
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(t.text2)
                }
            }
        }
        .navigationTitle("Agent policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    static let balancedPreset = """
default: ask
rules:
  - effect: deny
    kind: credential
  - effect: deny
    kind: network
  - effect: deny
    maxRisk: critical
  - effect: allow
    maxRisk: low
    kind: command
  - effect: ask
    kind: patch
"""

    static let strictPreset = """
default: ask
rules:
  - effect: deny
    kind: credential
  - effect: deny
    kind: network
  - effect: deny
    maxRisk: critical
  - effect: deny
    maxRisk: high
  - effect: ask
"""

    static let permissivePreset = """
default: ask
rules:
  - effect: deny
    kind: credential
  - effect: allow
    maxRisk: low
  - effect: ask
"""
}

#endif
