#if os(iOS)
import SwiftUI
import LancerCore

/// Password prompt shown before opening a password-authenticated SSH terminal.
struct TerminalPasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TerminalSessionCoordinator.self) private var terminalCoordinator

    let prompt: TerminalSessionCoordinator.PasswordPromptHost
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(prompt.host.displayAddress)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("SSH host")
                }
                Section {
                    SecureField("Password", text: $password)
                } header: {
                    Text("Password")
                } footer: {
                    Text("Password is kept in memory for this app session only.")
                }
            }
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        terminalCoordinator.cancelPasswordPrompt()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        terminalCoordinator.presentPasswordThenOpen(
                            host: prompt.host,
                            password: password,
                            startupCommand: prompt.startupCommand
                        )
                        dismiss()
                    }
                    .disabled(password.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
#endif
