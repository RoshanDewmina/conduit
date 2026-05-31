#if os(iOS)
import SwiftUI
import Observation
import ConduitCore
import SecurityKit
import DesignSystem

@MainActor @Observable
public final class KeysViewModel {
    public struct StoredKey: Identifiable, Hashable {
        public let tag: String
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
}

public struct KeysView: View {
    @State private var vm: KeysViewModel
    @State private var showImportSheet = false
    @Environment(\.conduitTokens) private var t

    private let store: KeyStore

    public init(viewModel: KeysViewModel, store: KeyStore) {
        _vm = State(initialValue: viewModel)
        self.store = store
    }

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
                    showImportSheet = true
                } label: {
                    Label("Import existing key…", systemImage: "square.and.arrow.down")
                        .foregroundStyle(t.accent)
                }
            }
            .listRowBackground(t.surf1)

            if let publicKey = vm.lastGeneratedPublic {
                Section("Last generated public key") {
                    Text(publicKey)
                        .font(.dsMonoPt(11))
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
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(key.tag)
                                    .font(.dsMonoPt(14))
                                    .foregroundStyle(t.text1)
                                    .textSelection(.enabled)
                                Text(key.fingerprint)
                                    .font(.dsMonoPt(11))
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
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("SSH key \(key.tag), fingerprint \(key.fingerprint)")
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
        .sheet(isPresented: $showImportSheet) {
            KeyImportView(store: store) {
                showImportSheet = false
                Task { await vm.reload() }
            }
        }
        .alert("Error", isPresented: .constant(vm.error != nil)) {
            Button("OK") { vm.error = nil }
        } message: { Text(vm.error ?? "") }
    }
}

#endif
