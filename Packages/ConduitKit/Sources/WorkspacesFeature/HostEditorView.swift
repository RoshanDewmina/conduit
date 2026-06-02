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
    public enum AuthChoice: String, CaseIterable, Identifiable, Hashable, Sendable {
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
                        DSSegmentedPicker(
                            options: HostEditorViewModel.AuthChoice.allCases.map { (label: $0.label, value: $0) },
                            selection: $vm.authChoice
                        )
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
                    DSButton("save host", variant: .accent, fullWidth: true, action: {
                        Task { await vm.save() }
                    })
                    .disabled(!vm.isValid)
                    .padding(.horizontal, 16)
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
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
            .padding(.horizontal, 16)
    }

    private var cardDivider: some View {
        DSDivider(.line)
    }

    private func inputRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        FocusableInputRow(label: label, placeholder: placeholder, text: text, mono: false, keyboard: .default, tokens: t)
    }

    private func monoInputRow(label: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        FocusableInputRow(label: label, placeholder: placeholder, text: text, mono: true, keyboard: keyboard, tokens: t)
    }

    private func shortKeyLabel(_ tag: String) -> String {
        let prefix = tag.prefix(8)
        return "\(prefix)…"
    }
}

// MARK: - FocusableInputRow
// BLOCKS field: uppercase label above a SQUARE bg-surfaceSunk bordered input.
// Turns the border accent-blue on focus (matching DSSearchField behaviour).

private struct FocusableInputRow: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let mono: Bool
    let keyboard: UIKeyboardType
    let tokens: ConduitTokens

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.dsMonoPt(10, weight: .medium))
                .tracking(10 * 0.08)
                .foregroundStyle(tokens.text3)

            HStack(spacing: 8) {
                if mono {
                    Text("$")
                        .font(.dsMonoPt(13, weight: .medium))
                        .foregroundStyle(tokens.accent)
                }
                TextField(placeholder, text: $text)
                    .font(mono ? .dsMonoPt(13) : .dsSansPt(13))
                    .foregroundStyle(tokens.text)
                    .tint(tokens.accent)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(tokens.surfaceSunk)
            .clipShape(RoundedRectangle(cornerRadius: tokens.r3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: tokens.r3, style: .continuous)
                    .strokeBorder(isFocused ? tokens.accent : tokens.border, lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private extension HostEditorViewModel {
    var isEditing: Bool { existingHost != nil }
}

#endif
