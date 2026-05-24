#if os(iOS)
import SwiftUI
import Observation
import ConduitCore
import SecurityKit
import DesignSystem

@MainActor @Observable
public final class KeysViewModel {
    public var keys: [String] = []
    public var lastGeneratedPublic: String?
    public var error: String?

    private let store: KeyStore
    public init(store: KeyStore) { self.store = store }

    public func reload() async {
        do { keys = try await store.allTags() }
        catch let err { self.error = err.localizedDescription }
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
                    ForEach(vm.keys, id: \.self) { tag in
                        HStack {
                            Image(systemName: "key").foregroundStyle(.tint)
                            Text(tag).font(.system(.callout, design: .monospaced))
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await vm.delete(tag) }
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
