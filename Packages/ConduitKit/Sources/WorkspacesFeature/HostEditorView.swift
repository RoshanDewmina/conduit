#if os(iOS)
import SwiftUI
import UIKit
import Observation
import ConduitCore
import DesignSystem
import PersistenceKit
import SecurityKit

@MainActor @Observable
public final class HostEditorViewModel {
    public enum AuthChoice: String, CaseIterable, Identifiable {
        case password
        case ed25519

        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .password: "Password"
            case .ed25519: "Ed25519 Key"
            }
        }
    }

    public var name: String = ""
    public var hostname: String = ""
    public var port: String = "22"
    public var username: String = ""
    public var authChoice: AuthChoice = .password
    public var keyTags: [String] = []
    public var selectedKeyTag: String?
    public var tmuxSessionName: String = ""
    public var startupCommand: String = ""
    public var tagsInput: String = ""
    public var preferredShell: String = ""
    public var autoResume: Bool = true
    public var saveError: String?

    private let repo: HostRepository
    private let keyStore: KeyStore
    private let existingHost: Host?
    private let onSaved: (Host) -> Void

    public init(
        repository: HostRepository,
        keyStore: KeyStore,
        existingHost: Host? = nil,
        onSaved: @escaping (Host) -> Void
    ) {
        self.repo = repository
        self.keyStore = keyStore
        self.existingHost = existingHost
        self.onSaved = onSaved
        if let existingHost {
            name = existingHost.name
            hostname = existingHost.hostname
            port = String(existingHost.port)
            username = existingHost.username
            tmuxSessionName = existingHost.tmuxSessionName ?? ""
            startupCommand = existingHost.startupCommand ?? ""
            tagsInput = existingHost.tags.joined(separator: ", ")
            preferredShell = existingHost.preferredShell ?? ""
            autoResume = existingHost.autoResume
            switch existingHost.authMethod {
            case .password, .agent:
                authChoice = .password
            case .ed25519(let keyID):
                authChoice = .ed25519
                selectedKeyTag = keyID.uuidString
            }
        }
    }

    public var isValid: Bool {
        let parsedPort = Int(port)
        let authIsValid = authChoice == .password || selectedKeyID != nil
        return !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !hostname.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && parsedPort.map { (1...65535).contains($0) } == true
            && authIsValid
    }

    public func loadKeys() async {
        do {
            let tags = try await keyStore.allTags()
            keyTags = tags.filter { UUID(uuidString: $0) != nil }.sorted()
            if selectedKeyTag == nil {
                selectedKeyTag = keyTags.first
            }
        } catch {
            keyTags = []
            if authChoice == .ed25519 {
                saveError = error.localizedDescription
            }
        }
    }

    public func save() async {
        guard isValid else { return }
        let authMethod: Host.AuthMethod
        switch authChoice {
        case .password:
            authMethod = .password
        case .ed25519:
            guard let keyID = selectedKeyID else {
                saveError = "Choose an Ed25519 key before saving."
                return
            }
            authMethod = .ed25519(keyID: keyID)
        }

        let tmux = tmuxSessionName.trimmingCharacters(in: .whitespaces)
        let startup = startupCommand.trimmingCharacters(in: .whitespaces)
        let shell = preferredShell.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = Host(
            id: existingHost?.id ?? .init(),
            name: name.trimmingCharacters(in: .whitespaces),
            hostname: hostname.trimmingCharacters(in: .whitespaces),
            port: Int(port) ?? 22,
            username: username.trimmingCharacters(in: .whitespaces),
            authMethod: authMethod,
            tags: parsedTags,
            hostKeyFingerprint: existingHost?.hostKeyFingerprint,
            preferredShell: shell.isEmpty ? nil : shell,
            tmuxSessionName: tmux.isEmpty ? nil : tmux,
            startupCommand: startup.isEmpty ? nil : startup,
            autoResume: autoResume,
            createdAt: existingHost?.createdAt ?? .now,
            lastConnectedAt: existingHost?.lastConnectedAt
        )
        do {
            try await repo.upsert(host)
            onSaved(host)
        } catch {
            saveError = error.localizedDescription
        }
    }

    private var selectedKeyID: KeyID? {
        guard let selectedKeyTag, let uuid = UUID(uuidString: selectedKeyTag) else { return nil }
        return KeyID(uuid)
    }

    var parsedTags: [String] {
        Array(Set(
            tagsInput
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        ))
        .sorted()
    }
}

public struct HostEditorView: View {
    @State private var vm: HostEditorViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: HostEditorViewModel) {
        _vm = State(initialValue: viewModel)
    }

    public var body: some View {
        Form {
            Section("Identity") {
                TextField("Display name", text: $vm.name)
                    .textInputAutocapitalization(.never)
                TextField("Tags (comma-separated)", text: $vm.tagsInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !vm.parsedTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(vm.parsedTags, id: \.self) { tag in
                                DSChip(tag, tone: .neutral, variant: .soft, size: .sm)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            Section("Connection") {
                TerminalSafeTextField(
                    "Hostname or IP",
                    text: $vm.hostname,
                    font: .monospacedSystemFont(ofSize: 17, weight: .regular)
                )
                .keyboardType(.URL)
                TextField("Port", text: $vm.port)
                    .keyboardType(.numberPad)
                TerminalSafeTextField(
                    "Username",
                    text: $vm.username,
                    font: .monospacedSystemFont(ofSize: 17, weight: .regular)
                )
            }
            Section("Session") {
                TerminalSafeTextField(
                    "tmux session name",
                    text: $vm.tmuxSessionName,
                    font: .monospacedSystemFont(ofSize: 17, weight: .regular)
                )
                Text("Optional. If set, Conduit attaches to this tmux session on connect, keeping your work alive across disconnects.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TerminalSafeTextField(
                    "startup command",
                    text: $vm.startupCommand,
                    font: .monospacedSystemFont(ofSize: 17, weight: .regular)
                )
                Text("Optional. Runs after connect (and any tmux attach). Example: cd ~/proj && claude.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle("Auto-resume agent session", isOn: $vm.autoResume)
                Text("When on, Conduit reattaches to the last Claude Code / Codex / Cursor / Grok / Gemini session running on this host.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TerminalSafeTextField(
                    "preferred shell (optional)",
                    text: $vm.preferredShell,
                    font: .monospacedSystemFont(ofSize: 17, weight: .regular)
                )
                Text("Optional shell override for this host, e.g. /bin/zsh or /usr/bin/fish.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Authentication") {
                Picker("Method", selection: $vm.authChoice) {
                    ForEach(HostEditorViewModel.AuthChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }

                if vm.authChoice == .ed25519 {
                    if vm.keyTags.isEmpty {
                        Text("Generate an Ed25519 key in Settings > SSH Keys, then return here to assign it to this host.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Key", selection: $vm.selectedKeyTag) {
                            ForEach(vm.keyTags, id: \.self) { tag in
                                Text(shortKeyLabel(tag)).tag(Optional(tag))
                            }
                        }
                    }
                } else {
                    Text("The password is requested at connect time and is not stored by this scaffold.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(vm.isEditing ? "Edit Host" : "Add Host")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await vm.save() }
                }
                .disabled(!vm.isValid)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .alert("Error", isPresented: .constant(vm.saveError != nil), actions: {
            Button("OK") { vm.saveError = nil }
        }, message: { Text(vm.saveError ?? "") })
        .task { await vm.loadKeys() }
    }

    private func shortKeyLabel(_ tag: String) -> String {
        let prefix = tag.prefix(8)
        return "\(prefix)..."
    }
}

private extension HostEditorViewModel {
    var isEditing: Bool { existingHost != nil }
}

#endif
