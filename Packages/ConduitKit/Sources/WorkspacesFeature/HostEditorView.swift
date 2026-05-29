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
        let host = Host(
            id: existingHost?.id ?? .init(),
            name: name.trimmingCharacters(in: .whitespaces),
            hostname: hostname.trimmingCharacters(in: .whitespaces),
            port: Int(port) ?? 22,
            username: username.trimmingCharacters(in: .whitespaces),
            authMethod: authMethod,
            tags: existingHost?.tags ?? [],
            hostKeyFingerprint: existingHost?.hostKeyFingerprint,
            preferredShell: existingHost?.preferredShell,
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
}

// MARK: - HostEditorView

public struct HostEditorView: View {
    @State private var vm: HostEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    public init(viewModel: HostEditorViewModel) {
        _vm = State(initialValue: viewModel)
    }

    public var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // ── Identity
                    sectionHead("Identity")
                    editorCard {
                        inputRow(label: "Display name", placeholder: "e.g. prod-server", text: $vm.name)
                    }
                    .padding(.bottom, 16)

                    // ── Connection
                    sectionHead("Connection")
                    editorCard {
                        monoInputRow(label: "Hostname or IP", placeholder: "192.168.1.1", text: $vm.hostname, keyboard: .URL)
                        cardDivider
                        monoInputRow(label: "Port", placeholder: "22", text: $vm.port, keyboard: .numberPad)
                        cardDivider
                        monoInputRow(label: "Username", placeholder: "ubuntu", text: $vm.username, keyboard: .default)
                    }
                    .padding(.bottom, 16)

                    // ── Authentication
                    sectionHead("Authentication")
                    editorCard {
                        HStack(spacing: 8) {
                            ForEach(HostEditorViewModel.AuthChoice.allCases) { choice in
                                let selected = vm.authChoice == choice
                                Text(choice.label)
                                    .font(.dsSansPt(13, weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? t.accentFg : t.text2)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(selected ? t.accent : t.surfaceSunk, in: Capsule())
                                    .contentShape(Capsule())
                                    .onTapGesture { vm.authChoice = choice }
                                    .animation(.easeInOut(duration: 0.15), value: vm.authChoice)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        if vm.authChoice == .ed25519 {
                            cardDivider
                            if vm.keyTags.isEmpty {
                                Text("Generate an Ed25519 key in Settings > SSH Keys, then return here to assign it to this host.")
                                    .font(.dsSansPt(13))
                                    .foregroundStyle(t.text3)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Key")
                                        .font(.dsSansPt(11, weight: .medium))
                                        .foregroundStyle(t.text3)
                                    ForEach(vm.keyTags, id: \.self) { tag in
                                        let selected = vm.selectedKeyTag == tag
                                        HStack {
                                            Text(shortKeyLabel(tag))
                                                .font(.dsMonoPt(13))
                                                .foregroundStyle(t.text)
                                            Spacer()
                                            if selected {
                                                DSIconView(.check, size: 14, color: t.accent)
                                            }
                                        }
                                        .padding(.vertical, 8)
                                        .contentShape(Rectangle())
                                        .onTapGesture { vm.selectedKeyTag = tag }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                        } else {
                            cardDivider
                            Text("Password is requested at connect time and is not stored.")
                                .font(.dsSansPt(13))
                                .foregroundStyle(t.text3)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                    }
                    .padding(.bottom, 16)

                    // ── Session
                    sectionHead("Session")
                    editorCard {
                        monoInputRow(label: "Tmux session", placeholder: "optional", text: $vm.tmuxSessionName, keyboard: .default)
                        cardDivider
                        monoInputRow(label: "Startup command", placeholder: "cd ~/proj && claude", text: $vm.startupCommand, keyboard: .default)
                        cardDivider
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-resume agent")
                                    .font(.dsSansPt(15))
                                    .foregroundStyle(t.text)
                                Text("Reattach to the last running agent session on connect.")
                                    .font(.dsSansPt(12))
                                    .foregroundStyle(t.text3)
                            }
                            Spacer()
                            Toggle("", isOn: $vm.autoResume)
                                .labelsHidden()
                                .tint(t.accent)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .padding(.bottom, 16)

                    // ── Error
                    if let err = vm.saveError {
                        HStack(spacing: 8) {
                            DSIconView(.alert, size: 14, color: t.danger)
                            Text(err).font(.dsSansPt(13)).foregroundStyle(t.danger)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                    }

                    // ── Save button
                    HStack {
                        Spacer()
                        DSButton("Save host", variant: .primary, action: {
                            Task { await vm.save() }
                        })
                        .disabled(!vm.isValid)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle(vm.isEditing ? "Edit Host" : "Add Host")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(t.accent)
            }
        }
        .task { await vm.loadKeys() }
    }

    // MARK: - Helpers

    private func sectionHead(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.dsSansPt(11, weight: .semibold))
            .foregroundStyle(t.text3)
            .tracking(0.5)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
    }

    private func editorCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(t.surface, in: RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
    }

    private var cardDivider: some View {
        t.border.frame(height: 0.5).padding(.horizontal, 16)
    }

    private func inputRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.dsSansPt(11, weight: .medium))
                .foregroundStyle(t.text3)
            TextField(placeholder, text: text)
                .font(.dsSansPt(15))
                .foregroundStyle(t.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func monoInputRow(label: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.dsSansPt(11, weight: .medium))
                .foregroundStyle(t.text3)
            TextField(placeholder, text: text)
                .font(.dsMonoPt(15))
                .foregroundStyle(t.text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func shortKeyLabel(_ tag: String) -> String {
        let prefix = tag.prefix(8)
        return "\(prefix)…"
    }
}

private extension HostEditorViewModel {
    var isEditing: Bool { existingHost != nil }
}

#endif
