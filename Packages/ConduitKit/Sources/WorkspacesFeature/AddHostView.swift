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

    // MARK: - Hosted / Conduit Cloud
    // Entitlement + upgrade-eligibility are injected (the entitlement source
    // lives in SettingsFeature, which this module must not depend on).
    private let hasCloudEntitlement: Bool
    private let cloudUpgradeEligible: Bool
    private let onUseHosted: (() -> Void)?

    // MARK: - Source mode (BYO SSH vs Conduit Cloud)
    @State private var mode: SourceMode = .byo

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

    // MARK: - Advanced navigation (HostEditorView push)
    @State private var showingAdvanced = false
    @State private var advancedVM: HostEditorViewModel?

    // MARK: - Key generation (V6)
    @State private var generatedKeyInfo: KeyStore.PublicKeyInfo?
    @State private var isGeneratingKey = false
    @State private var keyGenError: String?
    @State private var showCopiedSSHCopyId = false
    @State private var keyGenTask: Task<Void, Never>? = nil

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

    private enum SourceMode: Hashable, Sendable {
        case byo      // bring-your-own SSH host
        case hosted   // Conduit Cloud managed runtime
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
        hasCloudEntitlement: Bool = false,
        cloudUpgradeEligible: Bool = false,
        onCancel: @escaping () -> Void,
        onUseHosted: (() -> Void)? = nil,
        onConnectAndSave: @escaping (Host) -> Void
    ) {
        self.repository = repository
        self.keyStore = keyStore
        self.hasCloudEntitlement = hasCloudEntitlement
        self.cloudUpgradeEligible = cloudUpgradeEligible
        self.onCancel = onCancel
        self.onUseHosted = onUseHosted
        self.onConnectAndSave = onConnectAndSave
    }

    // MARK: - Body

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header
                DSDetailHeader("add host", onBack: onCancel)

                // ── Source mode picker (BYO SSH vs Conduit Cloud)
                modePicker
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                Text("This is the machine your coding agents control. Approvals for risky actions will come back to this phone.")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                // ── Clipboard banner (V3) — BYO only
                if mode == .byo, showClipboardBanner, let result = clipboardBannerResult {
                    clipboardBanner(result)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // ── Body
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if mode == .byo {
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
                        } else {
                            // ── Conduit Cloud panel
                            hostedPanel
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .transition(.opacity)
                        }

                        Spacer(minLength: 40)
                    }
                }

                // ── Footer CTA — BYO only (hosted has its own in-panel CTA)
                if mode == .byo {
                    footerCTA
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationBarHidden(true)
        .animation(.easeInOut(duration: 0.2), value: mode)
        .animation(.easeInOut(duration: 0.2), value: showClipboardBanner)
        .animation(.easeInOut(duration: 0.2), value: parsed != nil)
        .animation(.easeInOut(duration: 0.2), value: advancedExpanded)
        .task {
            // V3: Clipboard sniff
            await sniffClipboard()
            // Load existing keys
            await loadKeys()
        }
        .onDisappear {
            keyGenTask?.cancel()
            keyGenTask = nil
        }
    }

    // MARK: - Source mode picker

    private var modePicker: some View {
        DSSegmentedPicker(
            options: [
                (label: "bring your own", value: SourceMode.byo),
                (label: "conduit cloud", value: SourceMode.hosted),
            ],
            selection: $mode
        )
        .onChange(of: mode) { _, _ in Haptics.selection() }
    }

    // MARK: - Conduit Cloud panel (hosted)

    private var hostedPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ── Hero art: 3×3 pixel glyphs echoing the agent aesthetic
            hostedHeroArt

            // ── Headline
            VStack(alignment: .leading, spacing: 6) {
                Text("skip the setup")
                    .font(.dsDisplayPt(22, weight: .bold))
                    .foregroundStyle(t.text)
                Text("Run claude or codex on Conduit's managed infrastructure — no server to provision, patch, or keep online.")
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // ── Feature bullets
            VStack(alignment: .leading, spacing: 9) {
                hostedBullet("Managed runtime — agents run in the cloud, not on your hardware")
                hostedBullet("Metered usage, billed by the second — cancel anytime")
                hostedBullet("Your BYO SSH hosts stay free, always")
            }

            // ── State-dependent CTA
            if hasCloudEntitlement {
                hostedActiveCTA
            } else {
                hostedUpgradeCTA
            }
        }
    }

    private var hostedHeroArt: some View {
        HStack(spacing: 18) {
            Spacer(minLength: 0)
            PixelBox(state: .thinking,  size: 12, gap: 2, subdivisions: 2)
            PixelBox(state: .streaming, size: 12, gap: 2, subdivisions: 2)
            PixelBox(state: .approval,  size: 12, gap: 2, subdivisions: 2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(t.surfaceSunk)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.accent.opacity(0.35), lineWidth: 1)
        )
    }

    private func hostedBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(t.accent)
                .frame(width: 14, height: 16, alignment: .center)
            Text(text)
                .font(.dsSansPt(13))
                .foregroundStyle(t.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var hostedActiveCTA: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(t.ok).frame(width: 6, height: 6)
                Text("cloud active")
                    .font(.dsMonoPt(11, weight: .medium))
                    .tracking(11 * 0.08)
                    .textCase(.uppercase)
                    .foregroundStyle(t.ok)
            }

            DSButton(
                "use hosted runtime",
                systemImage: "sparkles",
                variant: .primary,
                mono: true,
                fullWidth: true
            ) {
                Haptics.success()
                onUseHosted?()
            }
        }
    }

    @ViewBuilder
    private var hostedUpgradeCTA: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Rectangle().fill(t.danger).frame(width: 5, height: 5)
                Text("no subscriptions on your own hardware")
                    .font(.dsMonoPt(10, weight: .medium))
                    .tracking(10 * 0.06)
                    .textCase(.uppercase)
                    .foregroundStyle(t.danger)
            }

            if cloudUpgradeEligible {
                Link(destination: URL(string: "https://conduit.dev/subscribe")!) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 14, weight: .semibold))
                        Text("upgrade to conduit cloud")
                            .font(.dsMonoPt(13, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(t.accentFg)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(t.accent)
                    .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                }
                .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
            } else {
                Text("Manage your Conduit Cloud subscription in Settings › Billing.")
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                    DSChip("port · \(p.port)", tone: .ok, variant: .solid, size: .sm)
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
                Haptics.light()
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
                        Haptics.selection()
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
                            let oneLiner = "echo '\(keyInfo.openSSH)' | ssh-copy-id -i /dev/stdin \(p.user)@\(p.host)\(p.port != 22 ? " -p \(p.port)" : "")"
                            UIPasteboard.general.string = oneLiner
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
                    keyGenTask = Task { await generateKey() }
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
            Text("Paste this command into your terminal on the server machine.")
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
        let rowLabel = HStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12))
                .foregroundStyle(parsed != nil ? t.text3 : t.text4)
            Text("more options — tmux, startup command, and more")
                .font(.dsMonoPt(11))
                .foregroundStyle(parsed != nil ? t.text3 : t.text4)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(parsed != nil ? t.text4 : t.text4.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        .opacity(parsed != nil ? 1.0 : 0.5)

        return Group {
            if parsed != nil {
                Button {
                    buildAdvancedVM()
                    showingAdvanced = true
                } label: {
                    rowLabel
                }
                .buttonStyle(.plain)
            } else {
                rowLabel
            }
        }
        .navigationDestination(isPresented: $showingAdvanced) {
            if let vm = advancedVM {
                HostEditorView(viewModel: vm)
            }
        }
    }

    private func buildAdvancedVM() {
        guard let p = parsed else { return }
        let vm = HostEditorViewModel(
            repository: repository,
            keyStore: keyStore,
            onSaved: { host in
                showingAdvanced = false
                onConnectAndSave(host)
            }
        )
        vm.name = p.displayName
        vm.hostname = p.host
        vm.port = String(p.port)
        vm.username = p.user
        advancedVM = vm
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
        // .task inherits the view's MainActor context; UIPasteboard is safe to read here.
        let str = UIPasteboard.general.string
        guard let str, !str.isEmpty else { return }
        if let result = parseSSHCommand(str) {
            clipboardBannerResult = result
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
        defer { isGeneratingKey = false }
        guard !Task.isCancelled else { return }
        do {
            let tag = UUID().uuidString
            let info = try await keyStore.generateEd25519(tag: tag, comment: "conduit@iphone")
            guard !Task.isCancelled else { return }
            generatedKeyInfo = info
            // Reload tags so the key picker shows up if user closes and reopens
            let tags = (try? await keyStore.allTags()) ?? []
            keyTags = tags.filter { UUID(uuidString: $0) != nil }.sorted()
            selectedKeyTag = tag
        } catch {
            keyGenError = error.localizedDescription
        }
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

        do {
            // Reuse an existing saved host (matched by host:port:user) instead of
            // minting a new id, so re-adding the same host updates it in place and
            // keeps its trusted host-key fingerprint rather than duplicating it.
            let existing = try await repository.all().first {
                $0.hostname.caseInsensitiveCompare(p.host) == .orderedSame
                    && $0.username == p.user
                    && $0.port == p.port
            }
            let host: Host
            if var found = existing {
                found.name = p.displayName
                found.authMethod = authMethod
                host = found
            } else {
                host = Host(
                    id: HostID(),
                    name: p.displayName,
                    hostname: p.host,
                    port: p.port,
                    username: p.user,
                    authMethod: authMethod,
                    tmuxSessionName: nil,
                    lastConnectedAt: nil
                )
            }
            try await repository.upsert(host)
            isSaving = false
            Haptics.success()
            onConnectAndSave(host)
        } catch {
            saveError = error.localizedDescription
            isSaving = false
            Haptics.error()
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
