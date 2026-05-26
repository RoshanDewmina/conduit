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
    public init(viewModel: KeysViewModel) { _vm = State(initialValue: viewModel) }

    public var body: some View {
        List {
            Section {
                Button {
                    Task { await vm.generate() }
                } label: { Label("Generate Ed25519 keypair", systemImage: "key.fill") }
            }

            if let publicKey = vm.lastGeneratedPublic {
                Section("Last generated public key") {
                    Text(publicKey)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                    Button("Copy") {
                        #if os(iOS)
                        UIPasteboard.general.string = publicKey
                        #endif
                        Haptics.selection()
                    }
                }
            }

            Section("Keys") {
                if vm.keys.isEmpty {
                    Text("No keys yet").foregroundStyle(.secondary)
                } else {
                    ForEach(vm.keys) { key in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "key")
                                .foregroundStyle(.tint)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(key.tag)
                                    .font(.system(.callout, design: .monospaced))
                                    .textSelection(.enabled)
                                Text(key.fingerprint)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
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
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await vm.delete(key.tag) }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .navigationTitle("SSH Keys")
        .contentMargins(.bottom, 72, for: .scrollContent)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
        .task { await vm.reload() }
    }
}

#endif
