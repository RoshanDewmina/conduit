#if os(iOS)
import SwiftUI
import LancerCore
import WorkspacesFeature

/// Simple sheet to add a password-authenticated SSH host for terminal access.
public struct SSHHostSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var quickConnect = ""
    @State private var name = ""
    @State private var hostname = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var password = ""
    @State private var parseHint: String?

    private let suggestedName: String?
    private let onSave: (Host, String) -> Void

    public init(suggestedName: String? = nil, onSave: @escaping (Host, String) -> Void) {
        self.suggestedName = suggestedName
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Quick connect") {
                    TextField("ssh user@host", text: $quickConnect)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: quickConnect) { _, newValue in
                            applyParsedCommand(newValue)
                        }
                    if let parseHint {
                        Text(parseHint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Host") {
                    TextField("Name", text: $name)
                    TextField("Hostname", text: $hostname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Authentication") {
                    SecureField("Password", text: $password)
                }
            }
            .navigationTitle("Add SSH Host")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if let suggestedName, name.isEmpty {
                    name = suggestedName
                }
            }
        }
    }

    private var canSave: Bool {
        !hostname.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && Int(port) != nil
            && !password.isEmpty
    }

    private func applyParsedCommand(_ text: String) {
        guard let parsed = parseSSHCommand(text) else {
            parseHint = text.isEmpty ? nil : "Could not parse — fill fields below"
            return
        }
        parseHint = "Parsed \(parsed.displayName)"
        username = parsed.user
        hostname = parsed.host
        port = String(parsed.port)
        if name.isEmpty || name == suggestedName {
            name = suggestedName ?? parsed.displayName
        }
    }

    private func save() {
        guard let portInt = Int(port), (1...65535).contains(portInt) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let host = Host(
            name: trimmedName.isEmpty ? "\(username)@\(hostname)" : trimmedName,
            hostname: hostname.trimmingCharacters(in: .whitespaces),
            port: portInt,
            username: username.trimmingCharacters(in: .whitespaces),
            authMethod: .password
        )
        onSave(host, password)
        dismiss()
    }
}
#endif
