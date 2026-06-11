#if os(iOS)
import SwiftUI
import ConduitCore

/// Loads live policy YAML from the bridge before showing ``PolicyEditorView``.
struct PolicyEditorBridgeScreen: View {
    let actions: BridgeSessionActions
    @State private var yamlText = PolicyEditorView.balancedPreset
    @State private var editorGeneration = 0
    @State private var loadError: String?

    var body: some View {
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
                : nil
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
