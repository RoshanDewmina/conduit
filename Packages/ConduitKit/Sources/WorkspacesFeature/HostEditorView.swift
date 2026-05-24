#if os(iOS)
import SwiftUI
import Observation
import ConduitCore
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
    public var saveError: String?

    private let repo: HostRepository
    private let keyStore: KeyStore
    private let onSaved: (Host) -> Void

    public init(repository: HostRepository, keyStore: KeyStore, onSaved: @escaping (Host) -> Void) {
        self.repo = repository
        self.keyStore = keyStore
        self.onSaved = onSaved
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
        let host = Host(
            name: name.trimmingCharacters(in: .whitespaces),
            hostname: hostname.trimmingCharacters(in: .whitespaces),
            port: Int(port) ?? 22,
            username: username.trimmingCharacters(in: .whitespaces),
            authMethod: authMethod,
            tags: [],
            tmuxSessionName: tmux.isEmpty ? nil : tmux
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
            }
            Section("Connection") {
                TextField("Hostname or IP", text: $vm.hostname)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                TextField("Port", text: $vm.port)
                    .keyboardType(.numberPad)
                TextField("Username", text: $vm.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section("Session") {
                TextField("tmux session name", text: $vm.tmuxSessionName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Optional. If set, Conduit attaches to this tmux session on connect, keeping your work alive across disconnects.")
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
        .navigationTitle("Add Host")
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

#endif
