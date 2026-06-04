#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem

/// View/edit remote policy YAML via daemon RPC (presets + raw editor).
public struct PolicyEditorView: View {
    @State private var yamlText: String
    private let cwd: String
    private let onReload: () async -> Void

    @Environment(\.conduitTokens) private var t

    public init(cwd: String, initialYAML: String, onReload: @escaping () async -> Void) {
        self.cwd = cwd
        _yamlText = State(initialValue: initialYAML)
        self.onReload = onReload
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
                    Task { await onReload() }
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
