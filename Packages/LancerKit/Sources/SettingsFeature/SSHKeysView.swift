#if os(iOS)
import SwiftUI
import UIKit
import SecurityKit
import DesignSystem

/// A loaded SSH key paired with its keystore tag for display + actions.
private struct SSHKeyEntry: Identifiable, Hashable {
    let tag: String
    let info: KeyStore.PublicKeyInfo
    var id: String { tag }
}

public struct SSHKeysView: View {
    private let keyStore: KeyStore

    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [SSHKeyEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    @State private var showGenerateSheet = false
    @State private var showImportSheet = false
    @State private var pendingDelete: SSHKeyEntry?

    public init(keyStore: KeyStore) {
        self.keyStore = keyStore
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("ssh keys", onBack: { dismiss() })

                    Text("Manage the SSH keypairs Lancer uses to authenticate to your hosts. Private key material never leaves the device keychain — only public keys and fingerprints are shown here.")
                        .font(.dsSansPt(14))
                        .foregroundStyle(t.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .padding(.bottom, 16)

                    sectionHead("KEYS")
                    if entries.isEmpty, !isLoading {
                        emptyState
                    } else {
                        card {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { hairline }
                                SSHKeyRow(
                                    entry: entry,
                                    onCopy: { copyPublicKey(entry) },
                                    onDelete: { pendingDelete = entry }
                                )
                            }
                        }
                    }

                    actionButtons

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.dsSansPt(12))
                            .foregroundStyle(t.text3)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 14)
                    }

                    Color.clear.frame(height: 36)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showGenerateSheet) {
            GenerateKeySheet(keyStore: keyStore) { message in
                statusMessage = message
                Task { await load() }
            } onError: { message in
                errorMessage = message
            }
        }
        .sheet(isPresented: $showImportSheet) {
            ImportKeySheet(keyStore: keyStore) { message in
                statusMessage = message
                Task { await load() }
            } onError: { message in
                errorMessage = message
            }
        }
        .task { await load() }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Delete this key?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let entry = pendingDelete { delete(entry) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("The private key will be permanently removed from the keychain. This cannot be undone.")
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let tags = try await keyStore.allTags()
            var loaded: [SSHKeyEntry] = []
            for tag in tags.sorted() {
                let info = try await keyStore.publicKey(tag: tag)
                loaded.append(SSHKeyEntry(tag: tag, info: info))
            }
            entries = loaded
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ entry: SSHKeyEntry) {
        Task {
            do {
                try await keyStore.delete(tag: entry.tag)
                statusMessage = "Deleted \(entry.tag)."
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func copyPublicKey(_ entry: SSHKeyEntry) {
        UIPasteboard.general.string = entry.info.openSSH
        statusMessage = "Public key for \(entry.tag) copied to clipboard."
    }

    // MARK: - Subviews

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button { showGenerateSheet = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "key.horizontal.fill")
                        .font(.dsSansPt(13, weight: .semibold))
                    Text("Generate Ed25519 key")
                        .font(.dsSansPt(14, weight: .medium))
                }
                .foregroundStyle(t.accentFg)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(t.accent)
                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Generate Ed25519 key")

            Button { showImportSheet = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.dsSansPt(13, weight: .semibold))
                    Text("Import private key")
                        .font(.dsSansPt(14, weight: .medium))
                }
                .foregroundStyle(t.text)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Import private key")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 28))
                .foregroundStyle(t.text4)
            Text("No SSH keys yet")
                .font(.dsSansPt(15, weight: .medium))
                .foregroundStyle(t.text2)
            Text("Generate a new Ed25519 key or import an existing private key to authenticate to your hosts.")
                .font(.dsSansPt(13))
                .foregroundStyle(t.text3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }

    private func sectionHead(_ title: String) -> some View {
        Text(title)
            .font(.dsMonoPt(11, weight: .medium))
            .tracking(11 * 0.10)
            .foregroundStyle(t.text3)
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 6)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
            .padding(.horizontal, 18)
    }

    private var hairline: some View {
        DSDivider(.soft, leadingInset: 16)
    }
}

// MARK: - Key row

private struct SSHKeyRow: View {
    let entry: SSHKeyEntry
    let onCopy: () -> Void
    let onDelete: () -> Void
    @Environment(\.lancerTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(t.accent)
                    .frame(width: 20, alignment: .center)
                Text(entry.tag)
                    .font(.dsSansPt(15, weight: .medium))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                        .font(.dsSansPt(13))
                        .foregroundStyle(t.danger)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete key \(entry.tag)")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.info.sha256Fingerprint)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(entry.info.openSSH)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .padding(.leading, 30)

            HStack(spacing: 8) {
                DSChip(entry.info.algorithm.rawValue, tone: .neutral, variant: .soft, size: .sm)
                Button { onCopy() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.dsSansPt(11))
                        Text("Copy public key")
                            .font(.dsSansPt(11, weight: .medium))
                    }
                    .foregroundStyle(t.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy public key for \(entry.tag)")
                Spacer(minLength: 0)
            }
            .padding(.leading, 30)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Generate sheet

private struct GenerateKeySheet: View {
    let keyStore: KeyStore
    let onDone: (String) -> Void
    let onError: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.lancerTokens) private var t

    @State private var tag = ""
    @State private var comment = ""
    @State private var isWorking = false
    @State private var generated: KeyStore.PublicKeyInfo?

    private var canGenerate: Bool {
        !tag.trimmingCharacters(in: .whitespaces).isEmpty && !isWorking
    }

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("generate key", onBack: { dismiss() })

                    sectionHead("NEW ED25519 KEY")
                    card {
                        fieldRow(label: "Name (tag)") {
                            TextField("e.g. work-laptop", text: $tag)
                                .font(.dsSansPt(14))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(10)
                                .background(t.surfaceSunk)
                                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                        }
                        hairline
                        fieldRow(label: "Comment (optional)") {
                            TextField("e.g. user@host", text: $comment)
                                .font(.dsSansPt(14))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(10)
                                .background(t.surfaceSunk)
                                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                        }
                    }

                    if let generated {
                        sectionHead("PUBLIC KEY")
                        card {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(generated.sha256Fingerprint)
                                    .font(.dsMonoPt(11))
                                    .foregroundStyle(t.text2)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(generated.openSSH)
                                    .font(.dsMonoPt(12))
                                    .foregroundStyle(t.text)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button {
                                    UIPasteboard.general.string = generated.openSSH
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.dsSansPt(12))
                                        Text("Copy public key")
                                            .font(.dsSansPt(13, weight: .medium))
                                    }
                                    .foregroundStyle(t.accent)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }

                        Text("Copy this public key onto your hosts (e.g. into ~/.ssh/authorized_keys), then close.")
                            .font(.dsSansPt(12))
                            .foregroundStyle(t.text3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 18)
                            .padding(.top, 14)
                    }

                    Button {
                        generate()
                    } label: {
                        Text(generated == nil ? "Generate" : "Generate another")
                            .font(.dsSansPt(15, weight: .semibold))
                            .foregroundStyle(canGenerate ? t.accentFg : t.text4)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(canGenerate ? t.accent : t.surfaceSunk)
                            .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGenerate)
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
                    .padding(.bottom, 36)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func generate() {
        let trimmedTag = tag.trimmingCharacters(in: .whitespaces)
        let trimmedComment = comment.trimmingCharacters(in: .whitespaces)
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let info = try await keyStore.generateEd25519(
                    tag: trimmedTag,
                    comment: trimmedComment.isEmpty ? nil : trimmedComment
                )
                generated = info
                onDone("Generated key \(trimmedTag).")
            } catch {
                onError(error.localizedDescription)
            }
        }
    }

    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.dsMonoPt(11, weight: .medium))
                .foregroundStyle(t.text3)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func sectionHead(_ title: String) -> some View {
        Text(title)
            .font(.dsMonoPt(11, weight: .medium))
            .tracking(11 * 0.10)
            .foregroundStyle(t.text3)
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 6)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
            .padding(.horizontal, 18)
    }

    private var hairline: some View {
        DSDivider(.soft, leadingInset: 16)
    }
}

// MARK: - Import sheet

private struct ImportKeySheet: View {
    let keyStore: KeyStore
    let onDone: (String) -> Void
    let onError: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.lancerTokens) private var t

    @State private var tag = ""
    @State private var comment = ""
    @State private var keyText = ""
    @State private var isWorking = false

    private var canImport: Bool {
        !tag.trimmingCharacters(in: .whitespaces).isEmpty
            && !keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isWorking
    }

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("import key", onBack: { dismiss() })

                    sectionHead("KEY DETAILS")
                    card {
                        fieldRow(label: "Name (tag)") {
                            TextField("e.g. legacy-server", text: $tag)
                                .font(.dsSansPt(14))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(10)
                                .background(t.surfaceSunk)
                                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                        }
                        hairline
                        fieldRow(label: "Comment (optional)") {
                            TextField("e.g. user@host", text: $comment)
                                .font(.dsSansPt(14))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(10)
                                .background(t.surfaceSunk)
                                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                        }
                    }

                    sectionHead("PRIVATE KEY")
                    card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Paste an OpenSSH or PEM private key")
                                .font(.dsMonoPt(11, weight: .medium))
                                .foregroundStyle(t.text3)
                            TextEditor(text: $keyText)
                                .font(.dsMonoPt(12))
                                .foregroundStyle(t.text)
                                .scrollContentBackground(.hidden)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .frame(minHeight: 160)
                                .padding(8)
                                .background(t.surfaceSunk)
                                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }

                    Text("The private key is stored only in this device's keychain and is never displayed again or sent to any agent.")
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)

                    Button {
                        performImport()
                    } label: {
                        Text("Import")
                            .font(.dsSansPt(15, weight: .semibold))
                            .foregroundStyle(canImport ? t.accentFg : t.text4)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(canImport ? t.accent : t.surfaceSunk)
                            .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canImport)
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
                    .padding(.bottom, 36)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func performImport() {
        let trimmedTag = tag.trimmingCharacters(in: .whitespaces)
        let trimmedComment = comment.trimmingCharacters(in: .whitespaces)
        let body = keyText
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                _ = try await keyStore.importPrivateKey(
                    tag: trimmedTag,
                    keyString: body,
                    comment: trimmedComment.isEmpty ? nil : trimmedComment
                )
                onDone("Imported key \(trimmedTag).")
                dismiss()
            } catch {
                onError(error.localizedDescription)
            }
        }
    }

    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.dsMonoPt(11, weight: .medium))
                .foregroundStyle(t.text3)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func sectionHead(_ title: String) -> some View {
        Text(title)
            .font(.dsMonoPt(11, weight: .medium))
            .tracking(11 * 0.10)
            .foregroundStyle(t.text3)
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 6)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
            .padding(.horizontal, 18)
    }

    private var hairline: some View {
        DSDivider(.soft, leadingInset: 16)
    }
}
#endif
