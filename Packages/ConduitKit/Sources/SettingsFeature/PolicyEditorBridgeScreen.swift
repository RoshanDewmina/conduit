#if os(iOS)
import SwiftUI
import ConduitCore
import SSHTransport

/// Loads live policy YAML from the bridge before showing ``PolicyEditorView``.
public struct PolicyEditorBridgeScreen: View {
    let actions: BridgeSessionActions
    var daemonChannel: DaemonChannel? = nil
    @State private var yamlText = PolicyEditorView.balancedPreset
    @State private var editorGeneration = 0
    @State private var loadError: String?

    public init(actions: BridgeSessionActions, daemonChannel: DaemonChannel? = nil) {
        self.actions = actions
        self.daemonChannel = daemonChannel
    }

    public var body: some View {
        PolicyEditorView(
            cwd: actions.policyCWD,
            initialYAML: yamlText,
            onReload: {
                do {
                    try await actions.reloadPolicy()
                    if actions.isConnected {
                        yamlText = try await actions.loadPolicyYAML()
                    }
                } catch {
                    loadError = error.localizedDescription
                }
            },
            onSave: actions.isConnected
                ? { body in try await actions.savePolicyYAML(body) }
                : nil,
            simulate: daemonChannel.map { ch in
                { @Sendable yaml, days in try await ch.simulatePolicy(yaml: yaml, periodDays: days) }
            }
        )
        .id(editorGeneration)
        .overlay(alignment: .top) {
            if let loadError {
                Text(loadError)
                    .font(.caption)
                    .padding(8)
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard actions.isConnected else { return }
        do {
            yamlText = try await actions.loadPolicyYAML()
            editorGeneration += 1
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

#endif
