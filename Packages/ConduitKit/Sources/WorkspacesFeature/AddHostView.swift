#if os(iOS)
import SwiftUI
import UIKit
import Observation
import ConduitCore
import DesignSystem
import PersistenceKit
import SecurityKit

// MARK: - AddHostView
// Paste-first "Fast Add-Host" sheet. Three fused UX modes:
//   (a) V1 — Paste-to-parse hero: mono $ field, keystroke parsing, confirm chips, "connect & save" CTA
//   (b) V3 — Clipboard-sniff banner: on appear reads UIPasteboard, shows top banner for ssh pattern
//   (c) V6 — Inline key-gen card: when advanced open + Ed25519 + no keys, show key-gen card

public struct AddHostView: View {
    // MARK: - Dependencies
    private let repository: HostRepository
    private let keyStore: KeyStore
    let onCancel: () -> Void
    let onConnectAndSave: (Host) -> Void

    // MARK: - Paste field state
    @State private var pasteText: String = ""
    @State private var parsed: SSHParseResult?

    // MARK: - Clipboard banner (V3)
    @State private var clipboardBannerResult: SSHParseResult?
    @State private var clipboardBannerDismissed = false

    // MARK: - Advanced disclosure (V6)
    @State private var advancedExpanded = false
    @State private var authChoice: AuthChoice = .password
    @State private var keyTags: [String] = []
    @State private var selectedKeyTag: String?

    // MARK: - Key generation (V6)
    @State private var generatedKeyInfo: KeyStore.PublicKeyInfo?
    @State private var isGeneratingKey = false
    @State private var keyGenError: String?
    @State private var showCopiedSSHCopyId = false

    // MARK: - Save / connect
    @State private var isSaving = false
    @State private var saveError: String?

    @Environment(\.conduitTokens) private var t
    @FocusState private var pasteFieldFocused: Bool

    private enum AuthChoice: String, CaseIterable, Identifiable {
        case password, ed25519
        var id: String { rawValue }
        var label: String { self == .password ? "Password" : "Ed25519" }
    }

    // Whether the clipboard banner should be shown
    private var showClipboardBanner: Bool {
        !clipboardBannerDismissed && clipboardBannerResult != nil
    }

    // Whether the key-gen card should be shown
    private var showKeyGenCard: Bool {
        advancedExpanded && authChoice == .ed25519 && keyTags.isEmpty
    }

    // CTA enabled when we have a valid parse
    private var canConnect: Bool { parsed != nil && !isSaving }

    public init(
        repository: HostRepository,
        keyStore: KeyStore,
        onCancel: @escaping () -> Void,
        onConnectAndSave: @escaping (Host) -> Void
    ) {
        self.repository = repository
        self.keyStore = keyStore
        self.onCancel = onCancel
        self.onConnectAndSave = onConnectAndSave
    }

    // MARK: - Body

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header
                DSDetailHeader("add host", onBack: onCancel)

                // ── Clipboard banner (V3)
                if showClipboardBanner, let result = clipboardBannerResult {
                    clipboardBanner(result)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // ── Body
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // ── Paste field section
                        pasteSection
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        // ── Advanced disclosure (V6)
                        advancedSection
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        // ── Error
                        if let err = saveError {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(t.danger)
                                Text(err)
                                    .font(.dsSansPt(13))
                                    .foregroundStyle(t.danger)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                        }

                        Spacer(minLength: 40)
                    }
                }

                // ── Footer CTA
                footerCTA
            }
        }
        .navigationBarHidden(true)
        .animation(.easeInOut(duration: 0.2), value: showClipboardBanner)
        .animation(.easeInOut(duration: 0.2), value: parsed != nil)
        .animation(.easeInOut(duration: 0.2), value: advancedExpanded)
        .task {
            // V3: Clipboard sniff
            await sniffClipboard()
            // Load existing keys
            await loadKeys()
        }
    }

    // MARK: - Paste section (V1)

    private var pasteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section label
            Text("SSH COMMAND")
                .font(.dsMonoPt(10, weight: .medium))
                .tracking(10 * 0.08)
                .foregroundStyle(t.text3)

            // Mono field with $ prefix
            HStack(spacing: 8) {
                Text("$")
                    .font(.dsMonoPt(14, weight: .semibold))
                    .foregroundStyle(t.accent)
                    .frame(width: 14, alignment: .leading)

                TextField("ssh user@host -p 2222", text: $pasteText)
                    .font(.dsMonoPt(13))
                    .foregroundStyle(t.text)
                    .tint(t.accent)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($pasteFieldFocused)
                    .onChange(of: pasteText) { _, newValue in
                        parsed = parseSSHCommand(newValue)
                    }
                    .submitLabel(.done)

                if !pasteText.isEmpty {
                    Button {
                        pasteText = ""
                        parsed = nil
                        pasteFieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(t.text4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(t.surfaceSunk)
            .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                    .strokeBorder(pasteFieldFocused ? t.accent : (parsed != nil ? t.ok : t.border), lineWidth: 1)
            )

            // ── Parsed confirm chips (V1)
            if let p = parsed {
                parsedChipsSection(p)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func parsedChipsSection(_ p: SSHParseResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PARSED")
                .font(.dsMonoPt(10, weight: .medium))
                .tracking(10 * 0.08)
                .foregroundStyle(t.ok)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    DSChip("user · \(p.user)", tone: .ok, variant: .solid, size: .sm)
                    DSChip("host · \(p.host)", tone: .ok, variant: .solid, size: .sm)
                    if p.port != 22 {
                        DSChip("port · \(p.port)", tone: .ok, variant: .solid, size: .sm)
                    }
                    if let idf = p.identityFile {
                        DSChip("key · \(URL(fileURLWithPath: idf).lastPathComponent)", tone: .accent, variant: .solid, size: .sm)
                    }
                }
            }

            // Name auto-set hint
            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .font(.system(size: 11))
                    .foregroundStyle(t.text4)
                Text("saved as \"\(p.displayName)\"")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text4)
            }
        }
    }

    // MARK: - Clipboard banner (V3)

    @ViewBuilder
    private func clipboardBanner(_ result: SSHParseResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(t.accent)
                Text("found in clipboard")
                    .font(.dsMonoPt(12, weight: .semibold))
                    .foregroundStyle(t.text)
                Spacer()
            }

            // Mono code block
            Text("ssh \(result.user)@\(result.host)\(result.port != 22 ? " -p \(result.port)" : "")")
                .font(.dsMonoPt(12))
                .foregroundStyle(t.text2)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(t.surfaceSunk)
                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1)
                )

            HStack(spacing: 8) {
                Spacer()
                DSButton("dismiss", variant: .ghost, size: .sm, mono: true) {
                    withAnimation { clipboardBannerDismissed = true }
                }
                DSButton("connect to \(result.host)", variant: .secondary, size: .sm, mono: true) {
                    fillFromResult(result)
                    withAnimation { clipboardBannerDismissed = true }
                }
            }
        }
        .padding(12)
        .background(t.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.accent.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Advanced disclosure (V6)

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Disclosure toggle row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    advancedExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: advancedExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(t.text3)
                        .frame(width: 16)
                    Text("advanced  (auth · tmux · startup)  —  optional")
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text3)
                    Spacer()
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if advancedExpanded {
                advancedContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var advancedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Auth segmented control
            authSegmentedControl

            // V6 key-gen card
            if showKeyGenCard {
                keyGenCard
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if authChoice == .ed25519 && !keyTags.isEmpty {
                // Key picker (existing keys)
                existingKeyPicker
            } else if authChoice == .password {
                Text("Password is requested at connect time and is not stored.")
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)
                    .padding(.horizontal, 4)
            }

            // "Full editor" push row
            fullEditorRow
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var authSegmentedControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AUTHENTICATION")
                .font(.dsMonoPt(10, weight: .medium))
                .tracking(10 * 0.08)
                .foregroundStyle(t.text3)

            HStack(spacing: 0) {
                ForEach(AuthChoice.allCases) { choice in
                    let selected = authChoice == choice
                    Button {
                        authChoice = choice
                        if choice == .ed25519 { Task { await loadKeys() } }
                    } label: {
                        Text(choice.label)
                            .font(.dsMonoPt(12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? t.text : t.text3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selected ? t.surface : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: t.r3 == 0 ? 2 : t.r3, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(t.surfaceSunk)
            .clipShape(RoundedRectangle(cornerRadius: t.r3 == 0 ? 4 : t.r3 + 2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r3 == 0 ? 4 : t.r3 + 2, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
        }
    }

    // MARK: - V6 key-gen card

    @ViewBuilder
    private var keyGenCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(t.accent)
                Text("key · no key yet — make one?")
                    .font(.dsMonoPt(12, weight: .semibold))
                    .foregroundStyle(t.text)
                Spacer()
            }

            if let keyInfo = generatedKeyInfo {
                // Generated key display
                Text(truncatedPubKey(keyInfo.openSSH))
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text2)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(t.surfaceSunk)
                    .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                            .strokeBorder(t.border, lineWidth: 1)
                    )

                HStack(spacing: 8) {
                    DSButton("copy public", variant: .secondary, size: .sm, mono: true) {
                        UIPasteboard.general.string = keyInfo.openSSH
                    }
                    if let p = parsed {
                        DSButton("ssh-copy-id", variant: .secondary, size: .sm, mono: true) {
                            let cmd = "ssh-copy-id -i /dev/stdin \(p.user)@\(p.host)\(p.port != 22 ? " -p \(p.port)" : "")"
                            let payload = keyInfo.openSSH + "\n| " + cmd
                            UIPasteboard.general.string = payload
                            showCopiedSSHCopyId = true
                        }
                    }
                }
            } else {
                // Generate button
                if let err = keyGenError {
                    Text(err)
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.danger)
                }

                DSButton(
                    "generate ed25519 key",
                    systemImage: "key.fill",
                    variant: .secondary,
                    size: .sm,
                    mono: true,
                    isLoading: isGeneratingKey
                ) {
                    Task { await generateKey() }
                }
                .disabled(isGeneratingKey)
            }

            // Footer note
            Text("Stored in the Keychain. Manage it in Library › SSH Keys.")
                .font(.dsSansPt(11))
                .foregroundStyle(t.text4)
        }
        .padding(12)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.accent.opacity(0.5), lineWidth: 1)
        )
        .alert("Copied", isPresented: $showCopiedSSHCopyId) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Paste the ssh-copy-id command into your terminal to install the key.")
        }
    }

    @ViewBuilder
    private var existingKeyPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("KEY")
                .font(.dsMonoPt(10, weight: .medium))
                .tracking(10 * 0.08)
                .foregroundStyle(t.text3)

            VStack(spacing: 0) {
                ForEach(keyTags, id: \.self) { tag in
                    let selected = selectedKeyTag == tag
                    HStack {
                        Text(shortKeyLabel(tag))
                            .font(.dsMonoPt(12))
                            .foregroundStyle(t.text)
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(t.accent)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedKeyTag = tag }

                    if tag != keyTags.last {
                        Rectangle().fill(t.divider).frame(height: 1).padding(.leading, 12)
                    }
                }
            }
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
        }
    }

    private var fullEditorRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12))
                .foregroundStyle(t.text3)
            Text("more options — tmux, startup command, and more")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(t.text4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        // Note: tapping this would push HostEditorView pre-filled.
        // For now it's informational; a NavigationLink version is left for Stream B polish.
        .opacity(0.6)
    }

    // MARK: - Footer CTA

    private var footerCTA: some View {
        VStack(spacing: 0) {
            Rectangle().fill(t.border).frame(height: 1)
            HStack {
                Spacer()
                DSButton(
                    "connect & save",
                    variant: .primary,
                    size: .lg,
                    isLoading: isSaving
                ) {
                    Task { await connectAndSave() }
                }
                .disabled(!canConnect)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(t.bg)
    }

    // MARK: - Actions

    private func fillFromResult(_ result: SSHParseResult) {
        let cmd = "ssh \(result.user)@\(result.host)\(result.port != 22 ? " -p \(result.port)" : "")"
        pasteText = cmd
        parsed = result
    }

    private func sniffClipboard() async {
        // UIPasteboard access is synchronous but may briefly pause UI; do it off the main thread, then publish.
        let str = await Task.detached { UIPasteboard.general.string }.value
        guard let str, !str.isEmpty else { return }
        if let result = parseSSHCommand(str) {
            await MainActor.run { clipboardBannerResult = result }
        }
    }

    private func loadKeys() async {
        do {
            let tags = try await keyStore.allTags()
            let uuidTags = tags.filter { UUID(uuidString: $0) != nil }.sorted()
            keyTags = uuidTags
            if selectedKeyTag == nil { selectedKeyTag = uuidTags.first }
        } catch {
            keyTags = []
        }
    }

    private func generateKey() async {
        isGeneratingKey = true
        keyGenError = nil
        do {
            let tag = UUID().uuidString
            let info = try await keyStore.generateEd25519(tag: tag, comment: "conduit@iphone")
            generatedKeyInfo = info
            // Reload tags so the key picker shows up if user closes and reopens
            let tags = (try? await keyStore.allTags()) ?? []
            keyTags = tags.filter { UUID(uuidString: $0) != nil }.sorted()
            selectedKeyTag = tag
        } catch {
            keyGenError = error.localizedDescription
        }
        isGeneratingKey = false
    }

    private func connectAndSave() async {
        guard let p = parsed else { return }
        isSaving = true
        saveError = nil

        let authMethod: Host.AuthMethod
        if authChoice == .ed25519, let tag = selectedKeyTag, let uuid = UUID(uuidString: tag) {
            authMethod = .ed25519(keyID: KeyID(uuid))
        } else {
            authMethod = .password
        }

        let newHost = Host(
            id: HostID(),
            name: p.displayName,
            hostname: p.host,
            port: p.port,
            username: p.user,
            authMethod: authMethod,
            tmuxSessionName: nil,
            lastConnectedAt: nil
        )

        do {
            try await repository.upsert(newHost)
            isSaving = false
            onConnectAndSave(newHost)
        } catch {
            saveError = error.localizedDescription
            isSaving = false
        }
    }

    // MARK: - Helpers

    private func truncatedPubKey(_ key: String) -> String {
        let parts = key.split(separator: " ")
        guard parts.count >= 2 else { return key }
        let b64 = String(parts[1])
        let preview = b64.prefix(20) + "…" + b64.suffix(6)
        let comment = parts.count >= 3 ? " " + parts[2] : ""
        return "\(parts[0]) \(preview)\(comment)"
    }

    private func shortKeyLabel(_ tag: String) -> String {
        "\(tag.prefix(8))…"
    }
}

#endif
