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
    @Environment(\.dismiss) private var dismiss

    private let store: KeyStore

    public init(viewModel: KeysViewModel, store: KeyStore) {
        _vm = State(initialValue: viewModel)
        self.store = store
    }

    public var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                DSDetailHeader("ssh keys", onBack: { dismiss() })

                ScrollView {
                    VStack(spacing: 16) {
                        // ── Actions
                        VStack(spacing: 0) {
                            actionRow(.key, "generate ed25519 keypair") { Task { await vm.generate() } }
                            DSDivider(.soft)
                            actionRow(.download, "import existing key…") { showImportSheet = true }
                        }
                        .blocksCard(t)

                        // ── Last generated public key
                        if let publicKey = vm.lastGeneratedPublic {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionHead("LAST GENERATED PUBLIC KEY")
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(publicKey)
                                        .font(.dsMonoPt(11))
                                        .foregroundStyle(t.text2)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                    copyButton("copy") { copy(publicKey) }
                                }
                                .padding(13)
                                .blocksCard(t)
                            }
                        }

                        // ── Keys
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHead("KEYS")
                            if vm.keys.isEmpty {
                                DSEmptyState(
                                    dotMatrix: .idle,
                                    title: "no keys yet",
                                    subtitle: "Generate or import an Ed25519 key to authenticate without a password."
                                )
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(Array(vm.keys.enumerated()), id: \.element.id) { idx, key in
                                        keyRow(key)
                                        if idx < vm.keys.count - 1 { DSDivider(.soft) }
                                    }
                                }
                                .blocksCard(t)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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

    // MARK: - Pieces

    private func sectionHead(_ s: String) -> some View {
        Text(s)
            .font(.dsDisplayPt(10, weight: .semibold))
            .tracking(10 * 0.12)
            .foregroundStyle(t.text3)
    }

    private func actionRow(_ icon: DSIcon, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: { action(); Haptics.selection() }) {
            HStack(spacing: 10) {
                DSIconView(icon, size: 15, color: t.accent)
                Text(label)
                    .font(.dsMonoPt(13))
                    .foregroundStyle(t.accent)
                Spacer()
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func keyRow(_ key: KeysViewModel.StoredKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            DSIconView(.key, size: 14, color: t.text3).padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(key.tag)
                    .font(.dsMonoPt(13))
                    .foregroundStyle(t.text)
                    .textSelection(.enabled)
                Text(key.fingerprint)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    copyButton("copy public key") { copy(key.openSSH) }
                    Button("delete") { Task { await vm.delete(key.tag) } }
                        .font(.dsMonoPt(11, weight: .medium))
                        .foregroundStyle(t.danger)
                        .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SSH key \(key.tag), fingerprint \(key.fingerprint)")
    }

    private func copyButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                DSIconView(.copy, size: 11, color: t.accent)
                Text(label).font(.dsMonoPt(11, weight: .medium)).foregroundStyle(t.accent)
            }
        }
        .buttonStyle(.plain)
    }

    private func copy(_ s: String) {
        #if os(iOS)
        UIPasteboard.general.string = s
        #endif
        Haptics.selection()
    }
}

// Square BLOCKS card: surface fill + 1px border, square corners.
private extension View {
    func blocksCard(_ t: ConduitTokens) -> some View {
        self
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
    }
}

#endif
