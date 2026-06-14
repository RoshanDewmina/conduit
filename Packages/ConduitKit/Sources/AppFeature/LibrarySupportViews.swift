#if os(iOS)
import SwiftUI
import DesignSystem
import KeysFeature
import SecurityKit

// MARK: - Screen 6: KeysManagementView

public struct KeysManagementView: View {
    let keyStore: KeyStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    @State private var vm: KeysViewModel
    @State private var copiedTag: String? = nil

    public init(keyStore: KeyStore) {
        self.keyStore = keyStore
        _vm = State(initialValue: KeysViewModel(store: keyStore))
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader("ssh keys", onBack: { dismiss() }) {
                    DSIconButton(.plus) {
                        Task { await vm.generate() }
                    }
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Generate dashed row
                        Button {
                            Task { await vm.generate() }
                        } label: {
                            HStack(spacing: 10) {
                                DSIconView(.plus, size: 14, color: t.accent)
                                Text("generate ed25519 key")
                                    .font(.dsMonoPt(13))
                                    .foregroundStyle(t.accent)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .overlay(
                                Rectangle()
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .foregroundStyle(t.accent.opacity(0.5))
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        }
                        .buttonStyle(.plain)

                        if vm.keys.isEmpty {
                            DSEmptyState(
                                icon: .key,
                                title: "no keys yet",
                                subtitle: "Generate an Ed25519 key to authenticate without passwords."
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 24)
                        } else {
                            DSListSectionHead("STORED KEYS", count: vm.keys.count)
                                .padding(.top, 8)

                            ForEach(vm.keys, id: \.id) { key in
                                keyRow(key)
                                DSDivider()
                            }
                        }
                    }
                }
            }

            // Copy confirmation toast
            if let tag = copiedTag {
                VStack {
                    Spacer()
                    Text("public key copied for \(tag)")
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.textOnDark)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.8))
                        .clipShape(Capsule())
                        .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { copiedTag = nil }
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .animation(.easeInOut(duration: 0.2), value: copiedTag)
        .task { await vm.reload() }
    }

    private func keyRow(_ key: KeysViewModel.StoredKey) -> some View {
        HStack(spacing: 12) {
            DSIconView(.key, size: 16, color: t.accent)
                .frame(width: 36, height: 36)
                .background(t.accentSoft)
                .clipShape(Rectangle())

            VStack(alignment: .leading, spacing: 4) {
                Text(key.tag)
                    .font(.dsMonoPt(13, weight: .medium))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                DSChip("ed25519", tone: .neutral, variant: .soft, size: .sm)
            }

            Spacer()

            Button {
                UIPasteboard.general.string = key.openSSH
                withAnimation { copiedTag = key.tag }
            } label: {
                DSIconView(.copy, size: 16, color: t.text3)
                    .frame(width: 36, height: 36)
                    .background(t.surface)
                    .clipShape(Rectangle())
                    .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

#endif
