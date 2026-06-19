#if os(iOS)
import SwiftUI
import ConduitCore
import TerminalEngine
import DesignSystem
import PersistenceKit

public struct SessionView: View {
    @State private var vm: SessionViewModel
    @State private var explainTarget: Block?
    @State private var explainText: String = ""
    @State private var isExplaining = false
    @State private var showingSnippetPalette = false
    @State private var availableSnippets: [Snippet] = []
    @State private var rawCtrlLatched = false
    @State private var showingPortForward = false
    @State private var showRawHistory = false
    @State private var keyboardExpanded = false
    @State private var expandedKeyboardTab: TerminalKeyboardPanel.Tab = .keys
    @State private var dictation = DictationEngine()
    @State private var showTmuxSheet = false
    @State private var liveInputActive = false
    @State private var tickHistory: [Double] = []
    @State private var showConnectOverlay = false
    @State private var connectOverlayPhase: SSHConnectPhase = .connecting
    @State private var hostKeyTrustInProgress = false

    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss
    private let onOpenWorkspace: (() -> Void)?

    public init(viewModel: SessionViewModel, onOpenWorkspace: (() -> Void)? = nil) {
        _vm = State(initialValue: viewModel)
        self.onOpenWorkspace = onOpenWorkspace
    }

    public var body: some View {
        coreView
            .sheet(item: $explainTarget) { block in explainSheet(block: block) }
            .alert(
                "Command Assistant",
                isPresented: Binding(
                    get: { vm.commandAssistantError != nil },
                    set: { if !$0 { vm.commandAssistantError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { vm.commandAssistantError = nil }
            } message: {
                let msg = vm.commandAssistantError ?? ""
                Text(msg)
            }
            .sheet(isPresented: $showingSnippetPalette) {
                SnippetPaletteSheet(
                    snippets: availableSnippets,
                    onInsert: { snippet, filledBody in
                        vm.pendingSnippetID = snippet.id
                        vm.inputText += filledBody
                        showingSnippetPalette = false
                    },
                    onDismiss: { showingSnippetPalette = false },
                    executeShellCommand: { cmd in
                        (try? await vm.session.executeCollected(cmd)) ?? ""
                    }
                )
            }
            // TOFU host-key confirmation. Presented from INSIDE SessionView so it
            // appears above the fullScreenCover (the ancestor `readyRoot` cannot
            // present a sheet over the cover — that was the B1 hard-hang). Preserves
            // the production prompt: connect only proceeds on explicit Trust; Cancel
            // rejects the key and leaves the session escapable via the overlay.
            .sheet(isPresented: Binding(
                get: { vm.pendingHostKeyFingerprint != nil },
                set: {
                    if !$0, vm.pendingHostKeyFingerprint != nil, !hostKeyTrustInProgress {
                        vm.rejectHostKey()
                    }
                }
            )) {
                if let fp = vm.pendingHostKeyFingerprint {
                    SessionHostKeyConfirmSheet(
                        hostName: vm.host.name,
                        fingerprint: fp,
                        onTrust: {
                            hostKeyTrustInProgress = true
                            Task {
                                await vm.trustHostKey()
                                await MainActor.run { hostKeyTrustInProgress = false }
                            }
                        },
                        onReject: {
                            hostKeyTrustInProgress = false
                            vm.rejectHostKey()
                        }
                    )
                    .presentationDetents([.medium])
                    .environment(\.conduitTokens, t)
                }
            }
            // Password re-entry after repeated auth failures (MAJOR-5). Presented
            // from INSIDE SessionView for the same reason as the TOFU sheet above:
            // once the session is live it sits in the fullScreenCover, and the
            // ancestor root cannot present a sheet over its own cover (the B1
            // family). The VM raises `awaitingPasswordRetry` after two consecutive
            // failures; Reconnect retries with the new password, Cancel dismisses.
            .sheet(isPresented: Binding(
                get: { vm.awaitingPasswordRetry },
                set: { if !$0 { vm.cancelPasswordRetry() } }
            )) {
                SessionPasswordRetrySheet(
                    hostName: vm.host.name,
                    onSubmit: { pw in Task { await vm.retryWithNewPassword(pw) } },
                    onCancel: { vm.cancelPasswordRetry() }
                )
                .presentationDetents([.medium])
                .environment(\.conduitTokens, t)
            }
    }

    // MARK: - Core view (split to keep body type-checkable)

    private var coreView: some View {
        ZStack {
            t.surf0.ignoresSafeArea()

            VStack(spacing: 0) {
                // Compact identity header (the Agent Island floats above it,
                // merging with the hardware island — see .overlay below).
                ChatHeaderView(
                    hostName: vm.host.name,
                    cwd: vm.cwd,
                    state: agentState,
                    blockedReason: vm.blockedReason,
                    // Back is pure navigation — it must NOT disconnect. The session
                    // (and its SSH connection) stays alive in the background so the
                    // active-session list + global HUD keep working; re-opening the
                    // row re-presents this same VM, still connected. Explicit
                    // disconnect lives in the header overflow menu / row long-press.
                    onBack: { dismiss() },
                    onDisconnect: {
                        Task { await vm.disconnect() }
                        dismiss()
                    },
                    onPortForward: { showingPortForward = true },
                    onOpenWorkspace: onOpenWorkspace,
                    // Manual reconnect: only surfaced when the connection is not
                    // healthy (dropped/failed/suspended), so the user isn't stranded
                    // on a dead session when automatic reconnect hasn't fired.
                    onReconnect: connectionIsUnhealthy
                        ? { Task { await vm.reconnect() } }
                        : nil
                )

                if case .reconnecting = vm.status {
                    reconnectBanner
                }

                if vm.isRaw {
                    rawTerminalContent
                } else {
                    ChatTranscriptView(
                        blocks: vm.blocks,
                        onLiveBytes: { bytes in
                            Task { await vm.sendKeystrokes(Array(bytes)) }
                        },
                        onLiveResize: { cols, rows in
                            Task { await vm.resizeUnifiedPTY(cols: cols, rows: rows) }
                        },
                        onExplain: { block in
                            explainText = ""
                            explainTarget = block
                        },
                        onRerun: { block in Task { await vm.rerun(block) } },
                        onCollapse: { block in
                            vm.blocks.toggleCollapsed(id: block.id)
                            Haptics.selection()
                        },
                        onStar: { block in
                            vm.blocks.toggleStarred(id: block.id)
                            Haptics.selection()
                        },
                        onLoadOlder: {
                            guard vm.hasOlderScrollback else { return }
                            Task { await vm.loadOlderScrollback() }
                        }
                    )
                }
            }

            // SSH connect orb overlay — stays visible briefly after connection
            if showConnectOverlay {
                SSHConnectOverlay(phase: connectOverlayPhase)
                    .ignoresSafeArea()
                    .onTapGesture {
                        switch connectOverlayPhase {
                        case .connected, .failed, .disconnected:
                            withAnimation(.easeOut(duration: 0.35)) { showConnectOverlay = false }
                        default:
                            break
                        }
                    }
            }
        }
        // No agent HUD overlay here: the session's own ChatHeaderView already
        // shows host · status, and an island here would overlap the camera
        // cutout. The slim app-wide AgentStatusHeader covers the tab screens.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !vm.isRaw {
                chatBottomBar
            }
        }
        .sheet(isPresented: $showingPortForward) {
            PortForwardView(viewModel: PortForwardViewModel(
                session: vm.session,
                hostID: vm.host.id
            ))
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTmuxSheet) {
            tmuxSessionSheet
        }
        .task {
            if let db = try? AppDatabase.openShared(),
               let snippets = try? await SnippetRepository(db: db).rankedForPalette(hostTags: vm.host.tags) {
                availableSnippets = snippets
            }
        }
        .onChange(of: vm.availableTmuxSessions) { _, sessions in
            if !sessions.isEmpty, vm.tmuxSessionName == nil {
                showTmuxSheet = true
            }
        }
        .onChange(of: vm.isExecutingUnified) { _, executing in
            if executing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    liveInputActive = true
                }
            }
            // Update tick history for HUD bars
            let snapshot = vm.blocks.blocks.last?.chunks.count ?? 0
            let norm = min(1.0, Double(snapshot) / 100.0)
            tickHistory.append(norm)
            if tickHistory.count > 24 { tickHistory.removeFirst() }
        }
        .onAppear {
            if vm.status == .connecting {
                connectOverlayPhase = .connecting
                showConnectOverlay = true
            }
        }
        .onChange(of: vm.status) { _, newStatus in
            switch newStatus {
            case .connecting:
                connectOverlayPhase = .connecting
                showConnectOverlay = true
            case .connected:
                connectOverlayPhase = .connected
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    withAnimation(.easeOut(duration: 0.4)) { showConnectOverlay = false }
                }
            case .failed(let reason):
                connectOverlayPhase = .failed(message: reason)
                showConnectOverlay = true
            case .disconnected:
                // New-host TOFU transitions to .disconnected with a pending
                // fingerprint — the host-key sheet handles that, so keep the
                // connecting overlay for a smooth continue after Trust. Otherwise
                // the connect was cancelled/rejected: show a dismissible
                // Disconnected overlay (tap to reveal the Back button) so the
                // user is never hard-stuck on "Connecting…".
                if vm.pendingHostKeyFingerprint == nil {
                    connectOverlayPhase = .disconnected
                    showConnectOverlay = true
                }
            default:
                break
            }
        }
        .focusable()
    }

    // MARK: - Derived agent state

    private var agentState: AgentState {
        switch vm.status {
        case .connecting:         return .thinking
        case .connected:          return vm.isExecutingUnified ? .streaming : .done
        case .disconnected:       return .offline
        case .suspended:          return .offline
        case .reconnecting:       return .thinking
        case .failed:             return .error
        }
    }

    // True when the connection is dropped/failed and a manual reconnect makes
    // sense. `.reconnecting` is excluded — its banner already drives auto-retry.
    private var connectionIsUnhealthy: Bool {
        switch vm.status {
        case .disconnected, .suspended, .failed: return true
        case .connecting, .connected, .reconnecting: return false
        }
    }

    // MARK: - Bottom bar (ChatInputBar + keyboard accessory)

    private var chatBottomBar: some View {
        VStack(spacing: 0) {
            // Keyboard accessory rail (Tab, arrows, Ctrl keys)
            HStack(spacing: 6) {
                KeyboardAccessoryRail(ctrlLatched: $rawCtrlLatched) { bytes in
                    Task { await vm.sendKeystrokes(bytes) }
                }
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)

                expandKeyboardButton

                Button { showRawHistory = true } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title3)
                        .foregroundStyle(t.text3)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(vm.commandHistory.isEmpty)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(t.surf1)
            .overlay(Rectangle().fill(t.surf3.opacity(0.5)).frame(height: 0.5), alignment: .top)

            if keyboardExpanded {
                TerminalKeyboardPanel(
                    selectedTab: $expandedKeyboardTab,
                    ctrlLatched: $rawCtrlLatched,
                    commandHistory: vm.commandHistory,
                    snippets: availableSnippets,
                    onBytes: { bytes in Task { await vm.sendKeystrokes(bytes) } },
                    onPaste: { if let b = pasteBytes() { Task { await vm.sendKeystrokes(b) } } },
                    onRunHistory: { cmd in Task { await vm.sendToShell(cmd) } },
                    onInsertSnippet: { snippet in vm.inputText += snippet.body },
                    onDismiss: { collapseKeyboard() }
                )
                .frame(height: 300)
                .transition(.move(edge: .bottom))
            } else {
                // Chat input pill
                ChatInputBar(
                    inputText: $vm.inputText,
                    isExecuting: vm.isExecutingUnified,
                    isTranslating: vm.isTranslating,
                    isDisconnected: vm.status != .connected,
                    onSubmit: { Task { await vm.submit() } },
                    onSnippet: { showingSnippetPalette = true },
                    onMic: {
                        Task {
                            if dictation.isListening { dictation.stop() }
                            else { await dictation.start { text in vm.inputText = text } }
                        }
                    },
                    isMicActive: dictation.isListening,
                    onSendLiveKey: { bytes in Task { await vm.sendKeystrokes(bytes) } },
                    liveInputActive: $liveInputActive
                )
            }
        }
        .sheet(isPresented: $showRawHistory) { rawHistorySheet }
    }

    // MARK: - Expandable keyboard helpers

    /// Toggle between the system keyboard and the expanded key panel.
    private var expandKeyboardButton: some View {
        Button {
            if keyboardExpanded { collapseKeyboard() } else { expandKeyboard() }
        } label: {
            Image(systemName: keyboardExpanded ? "keyboard.chevron.compact.down" : "keyboard.chevron.compact.up")
                .font(.title3)
                .foregroundStyle(keyboardExpanded ? t.accent : t.text3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(keyboardExpanded ? "Hide key panel" : "Show key panel")
    }

    private func expandKeyboard() {
        dismissSystemKeyboard()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            keyboardExpanded = true
        }
    }

    private func collapseKeyboard() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            keyboardExpanded = false
        }
    }

    private func dismissSystemKeyboard() {
        liveInputActive = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }

    /// Clipboard bytes for the panel's paste key. Wraps multi-line text in
    /// bracketed-paste markers; single-line text is sent verbatim (no newline,
    /// so it lands at the prompt without auto-executing).
    private func pasteBytes() -> [UInt8]? {
        guard let s = UIPasteboard.general.string, !s.isEmpty else { return nil }
        if s.contains("\n") {
            return Array(("\u{1B}[200~" + s + "\u{1B}[201~").utf8)
        }
        return Array(s.utf8)
    }

    // MARK: - Raw terminal content

    @ViewBuilder
    private var rawTerminalContent: some View {
        if let handle = vm.rawFeedHandle {
            RawTerminalView(
                feedHandle: handle,
                onUserBytes: { bytes in
                    let typedBytes = Array(bytes)
                    Task { @MainActor in
                        let outgoing = consumeRawCtrlLatch(typedBytes)
                        try? await vm.activeShell?.send(outgoing)
                    }
                },
                onResize: { cols, rows in
                    Task { try? await vm.activeShell?.resize(cols: cols, rows: rows) }
                }
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        KeyboardAccessoryRail(ctrlLatched: $rawCtrlLatched) { bytes in
                            Task { try? await vm.activeShell?.send(bytes) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)

                        expandKeyboardButton

                        Button { showRawHistory = true } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .disabled(vm.commandHistory.isEmpty)
                    }
                    .background(t.termSurface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                    if keyboardExpanded {
                        TerminalKeyboardPanel(
                            selectedTab: $expandedKeyboardTab,
                            ctrlLatched: $rawCtrlLatched,
                            commandHistory: vm.commandHistory,
                            snippets: availableSnippets,
                            onBytes: { bytes in Task { try? await vm.activeShell?.send(bytes) } },
                            onPaste: { if let b = pasteBytes() { Task { try? await vm.activeShell?.send(b) } } },
                            onRunHistory: { cmd in Task { await vm.sendToShell(cmd) } },
                            onInsertSnippet: { snippet in
                                Task { try? await vm.activeShell?.send(Array(snippet.body.utf8)) }
                            },
                            onDismiss: { collapseKeyboard() }
                        )
                        .frame(height: 300)
                        .transition(.move(edge: .bottom))
                    }
                }
                .background(t.termBg)
            }
            .sheet(isPresented: $showRawHistory) { rawHistorySheet }
        } else {
            ProgressView("Opening terminal…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Reconnect banner

    private var reconnectBanner: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7)
            Text("Reconnecting…").font(.caption.weight(.medium)).foregroundStyle(t.text2)
            Spacer()
            Button("Cancel") { Task { await vm.disconnect() } }
                .font(.caption).buttonStyle(.bordered).controlSize(.mini)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(t.warn.opacity(0.12))
    }

    // MARK: - Raw history sheet

    private var rawHistorySheet: some View {
        NavigationStack {
            List {
                ForEach(vm.commandHistory.suffix(50).reversed(), id: \.self) { cmd in
                    Button {
                        showRawHistory = false
                        Task { await vm.sendToShell(cmd) }
                    } label: {
                        Text(cmd)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Command History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showRawHistory = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Tmux sheet

    private var tmuxSessionSheet: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // ── Header
                HStack(alignment: .top, spacing: t.s4) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tmux Sessions")
                            .font(.dsDisplayPt(22, weight: .bold))
                            .foregroundStyle(t.text)
                        Text("Reattach to a session still running on this host to restore its programs and scrollback.")
                            .font(.dsSansPt(13))
                            .foregroundStyle(t.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    DSButton("Skip", variant: .ghost, size: .sm) { showTmuxSheet = false }
                }
                .padding(.horizontal, t.s6)
                .padding(.top, t.s7)
                .padding(.bottom, t.s5)

                // ── Section head
                Text("AVAILABLE SESSIONS")
                    .font(.dsMonoPt(11))
                    .tracking(0.8)
                    .foregroundStyle(t.text3)
                    .padding(.horizontal, t.s6)
                    .padding(.bottom, t.s2)

                // ── Session cards
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(vm.availableTmuxSessions, id: \.self) { name in
                            Button {
                                vm.attachToTmuxSession(name)
                                showTmuxSheet = false
                            } label: {
                                HStack(spacing: t.s4) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                                            .fill(t.accentSoft)
                                            .frame(width: 34, height: 34)
                                        DSIconView(.terminal, size: 16, color: t.accent)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(name)
                                            .font(.dsMonoPt(15, weight: .medium))
                                            .foregroundStyle(t.text)
                                        Text("tmux session")
                                            .font(.dsSansPt(12))
                                            .foregroundStyle(t.text3)
                                    }
                                    Spacer(minLength: 0)
                                    Text("ATTACH")
                                        .font(.dsMonoPt(11, weight: .medium))
                                        .tracking(0.6)
                                        .foregroundStyle(t.accent)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(t.text4)
                                }
                                .padding(.horizontal, t.s5)
                                .padding(.vertical, t.s4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if name != vm.availableTmuxSessions.last {
                                Rectangle().fill(t.divider).frame(height: 1)
                                    .padding(.leading, t.s5 + 34 + t.s4)
                            }
                        }
                    }
                    .background(t.surface)
                    .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                            .strokeBorder(t.border, lineWidth: 1)
                    )
                    .padding(.horizontal, t.s5)
                    .padding(.bottom, t.s6)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Explain sheet

    private func explainSheet(block: Block) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Command").font(.caption).foregroundStyle(.secondary)
                        Text(block.command)
                            .font(.system(.body, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(t.surf2)
                            .clipShape(RoundedRectangle(cornerRadius: t.radiusSM))
                    }
                    if let status = block.exitStatus {
                        Text("Exit code \(status.code)").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    HStack {
                        Image(systemName: "sparkles").foregroundStyle(.tint)
                        Text("AI explanation").font(.headline)
                        Spacer()
                        if isExplaining { ProgressView().scaleEffect(0.7) }
                    }
                    Text(explainText.isEmpty ? "Tap Explain to analyze this command." : explainText)
                        .font(.body).frame(maxWidth: .infinity, alignment: .leading)
                    if !isExplaining {
                        Button {
                            Task { await runExplain(block: block) }
                        } label: {
                            Label(explainText.isEmpty ? "Explain" : "Explain again", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
            .navigationTitle("Explain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { explainTarget = nil }
                }
            }
            .task { await runExplain(block: block) }
        }
    }

    private func runExplain(block: Block) async {
        explainText = ""
        isExplaining = true
        defer { isExplaining = false }
        do {
            for try await chunk in vm.explain(block) { explainText += chunk }
        } catch {
            explainText = error.localizedDescription
        }
    }

    private func consumeRawCtrlLatch(_ bytes: [UInt8]) -> [UInt8] {
        guard rawCtrlLatched, let first = bytes.first else { return bytes }
        rawCtrlLatched = false
        var outgoing = bytes
        if (0x41...0x5a).contains(first) || (0x61...0x7a).contains(first) {
            outgoing[0] = first & 0x1f
        }
        return outgoing
    }
}

// MARK: - TOFU host-key confirmation (presented from within SessionView)
//
// Self-contained so SessionFeature need not depend on WorkspacesFeature (which
// would also be linked into the Live Activity widget extension). Mirrors the
// production `HostKeyConfirmSheet` UX: explicit Trust & Connect / Cancel, no
// auto-trust, fingerprint shown for out-of-band verification.
private struct SessionPasswordRetrySheet: View {
    let hostName: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var password = ""
    @Environment(\.conduitTokens) private var t

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    DSIconView(.alertTri, size: 24, color: t.danger)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Authentication Failed")
                            .font(.dsSansPt(16, weight: .semibold))
                            .foregroundStyle(t.text)
                        Text("Couldn't sign in to \(hostName). Re-enter the password to try again.")
                            .font(.dsSansPt(13))
                            .foregroundStyle(t.text3)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Password")
                        .font(.dsSansPt(11, weight: .medium))
                        .foregroundStyle(t.text3)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit { if !password.isEmpty { onSubmit(password) } }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: t.radiusSM, style: .continuous))
                        .foregroundStyle(t.text)
                }

                Spacer()

                VStack(spacing: 10) {
                    DSButton("Reconnect", variant: .primary) {
                        if !password.isEmpty { onSubmit(password) }
                    }
                    DSButton("Cancel", variant: .secondary, action: onCancel)
                }
            }
            .padding()
            .background(t.bg)
            .navigationTitle("Re-authenticate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(t.accent)
                }
            }
        }
    }
}

private struct SessionHostKeyConfirmSheet: View {
    let hostName: String
    let fingerprint: String
    let onTrust: () -> Void
    let onReject: () -> Void

    @Environment(\.conduitTokens) private var t

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    DSIconView(.shield, size: 24, color: t.warn)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unknown Host Key")
                            .font(.dsSansPt(16, weight: .semibold))
                            .foregroundStyle(t.text)
                        Text("The authenticity of \(hostName) cannot be established.")
                            .font(.dsSansPt(13))
                            .foregroundStyle(t.text3)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Fingerprint (SHA256)")
                        .font(.dsSansPt(11, weight: .medium))
                        .foregroundStyle(t.text3)
                    Text(fingerprint)
                        .font(.dsMonoPt(12))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: t.radiusSM, style: .continuous))
                        .foregroundStyle(t.text2)
                }

                Text("If you trust this host, tap **Trust & Connect**. If you are not expecting this fingerprint, tap **Cancel** and verify out-of-band.")
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)

                Spacer()

                VStack(spacing: 10) {
                    DSButton("Trust & Connect", variant: .primary, action: onTrust)
                    DSButton("Cancel", variant: .secondary, action: onReject)
                }
            }
            .padding()
            .background(t.bg)
            .navigationTitle("Verify Host")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onReject)
                        .foregroundStyle(t.accent)
                }
            }
        }
    }
}

#endif
