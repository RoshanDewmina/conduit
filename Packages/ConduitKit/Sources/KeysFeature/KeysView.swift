#if os(iOS)
import SwiftUI
import Observation
import ConduitCore
import SecurityKit
import DesignSystem
import UniformTypeIdentifiers

@MainActor @Observable
public final class KeysViewModel {
    public struct StoredKey: Identifiable, Hashable {
        public let tag: String
        public let algorithm: KeyStore.KeyAlgorithm
        public let openSSH: String
        public let fingerprint: String

        public var id: String { tag }
    }

    public var keys: [StoredKey] = []
    public var lastGeneratedPublic: String?
    public var error: String?

    private let store: KeyStore
    public init(store: KeyStore) { self.store = store }

    public func reload() async {
        do {
            let tags = try await store.allTags()
            var loaded: [StoredKey] = []
            for tag in tags {
                let info = try await store.publicKey(tag: tag)
                loaded.append(StoredKey(
                    tag: tag,
                    algorithm: info.algorithm,
                    openSSH: info.openSSH,
                    fingerprint: info.sha256Fingerprint
                ))
            }
            keys = loaded.sorted { $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
        } catch let err {
            self.error = err.localizedDescription
        }
    }

    public func generate() async {
        let tag = KeyID().uuidString
        do {
            let info = try await store.generateEd25519(tag: String(tag))
            lastGeneratedPublic = info.openSSH
            await reload()
            Haptics.success()
        } catch let err {
            self.error = err.localizedDescription
            Haptics.error()
        }
    }

    public func delete(_ tag: String) async {
        do {
            try await store.delete(tag: tag)
            await reload()
        } catch let err { self.error = err.localizedDescription }
    }

    public func importFromText(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let tag = KeyID().uuidString
        do {
            _ = try await store.importPrivateKey(tag: tag, keyString: trimmed, comment: tag)
            await reload()
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
    }

    public func importFromFile(_ url: URL) async {
        do {
            let data = try Data(contentsOf: url)
            let tag = KeyID().uuidString
            _ = try await store.importPrivateKey(tag: tag, keyData: data, comment: tag)
            await reload()
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
    }
}

public struct KeysView: View {
    @State private var vm: KeysViewModel
    @Environment(\.conduitTokens) private var t
    @State private var importText = ""
    @State private var isShowingPasteImport = false
    @State private var isShowingFileImporter = false

    public init(viewModel: KeysViewModel) { _vm = State(initialValue: viewModel) }

    public var body: some View {
        List {
            Section {
                Button {
                    Task { await vm.generate() }
                } label: {
                    Label("Generate Ed25519 keypair", systemImage: "key.fill")
                        .foregroundStyle(t.accent)
                }

                Button {
                    importText = ""
                    isShowingPasteImport = true
                } label: {
                    Label("Import key (paste)", systemImage: "doc.on.clipboard")
                        .foregroundStyle(t.accent)
                }

                Button {
                    isShowingFileImporter = true
                } label: {
                    Label("Import key (file)", systemImage: "square.and.arrow.down")
                        .foregroundStyle(t.accent)
                }
            }
            .listRowBackground(t.surf1)

            if let publicKey = vm.lastGeneratedPublic {
                Section("Last generated public key") {
                    Text(publicKey)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(t.text2)
                        .textSelection(.enabled)
                    Button("Copy") {
                        #if os(iOS)
                        UIPasteboard.general.string = publicKey
                        #endif
                        Haptics.selection()
                    }
                    .foregroundStyle(t.accent)
                }
                .listRowBackground(t.surf1)
            }

            Section("Keys") {
                if vm.keys.isEmpty {
                    Text("No keys yet")
                        .foregroundStyle(t.text3)
                        .listRowBackground(t.surf1)
                } else {
                    ForEach(vm.keys) { key in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "key")
                                .foregroundStyle(t.accent)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(key.tag)
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(t.text1)
                                    .textSelection(.enabled)
                                Text(key.algorithmLabel)
                                    .font(.caption2)
                                    .foregroundStyle(t.text3)
                                Text(key.fingerprint)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(t.text3)
                                    .textSelection(.enabled)
                                Button("Copy public key") {
                                    #if os(iOS)
                                    UIPasteboard.general.string = key.openSSH
                                    #endif
                                    Haptics.selection()
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .tint(t.accent)
                                .disabled(key.openSSH.contains("<private-key-imported>"))
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await vm.delete(key.tag) }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    .listRowBackground(t.surf1)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(t.surf0)
        .navigationTitle("SSH Keys")
        .contentMargins(.bottom, 72, for: .scrollContent)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
        .task { await vm.reload() }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.data, .text, .item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let didStart = url.startAccessingSecurityScopedResource()
                Task {
                    await vm.importFromFile(url)
                    if didStart { url.stopAccessingSecurityScopedResource() }
                }
            case .failure(let error):
                vm.error = error.localizedDescription
            }
        }
        .sheet(isPresented: $isShowingPasteImport) {
            NavigationStack {
                Form {
                    Section("Private key text") {
                        TextEditor(text: $importText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 220)
                    }
                }
                .navigationTitle("Import Key")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isShowingPasteImport = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") {
                            let text = importText
                            isShowingPasteImport = false
                            Task { await vm.importFromText(text) }
                        }
                        .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Error", isPresented: .constant(vm.error != nil)) {
            Button("OK") { vm.error = nil }
        } message: { Text(vm.error ?? "") }
    }
}

private extension KeysViewModel.StoredKey {
    var algorithmLabel: String {
        switch algorithm {
        case .ed25519: return "Ed25519"
        case .rsa: return "RSA"
        case .ecdsaP256: return "ECDSA P-256"
        case .ecdsaP384: return "ECDSA P-384"
        case .ecdsaP521: return "ECDSA P-521"
        }
    }
}

#endif
