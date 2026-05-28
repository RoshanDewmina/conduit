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
    @State private var dictation = DictationEngine()
    @State private var showTmuxSheet = false
    /// Flipped to `true` to trigger keyboard open on the `LivePromptInputView`.
    @State private var liveInputActive = false

    public init(viewModel: SessionViewModel) {
        _vm = State(initialValue: viewModel)
    }

    public var body: some View {
        ZStack {
            // Warp-style dark wallpaper underneath the block stack.
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.07, blue: 0.09),
                    Color(red: 0.10, green: 0.11, blue: 0.13)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                statusBar
                if case .reconnecting = vm.status {
                    reconnectBanner
                }
                if vm.isRaw {
                    rawTerminalContent
                } else {
                    blockScroll
                }
            }
        }
        .preferredColorScheme(.dark)
        // Phase 0.5: composer / live-input shown in safeAreaInset so it
        // sits flush at the bottom edge and keyboard-avoidance is automatic.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !vm.isRaw {
                accessoryDock
            }
        }
        .toolbar {
            // Phase 5: mode toggle removed — alt-screen switch is automatic.
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingPortForward = true
                } label: {
                    Label("Port Forwarding", systemImage: "arrow.left.arrow.right")
                }
                .disabled(vm.status != .connected)
            }
        }
        .sheet(isPresented: $showingPortForward) {
            PortForwardView(viewModel: PortForwardViewModel(
                session: vm.session,
                hostID: vm.host.id
            ))
            .presentationDetents([.medium, .large])
        }
        // Phase 6: tmux session picker sheet
        .sheet(isPresented: $showTmuxSheet) {
            tmuxSessionSheet
        }
        .task {
            if let db = try? AppDatabase.openShared(),
               let snippets = try? await SnippetRepository(db: db).all() {
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
                // Give SwiftUI a tick to commit the executingComposer layout
                // before requesting first responder on the LiveInputUIView.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    liveInputActive = true
                }
            }
        }
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
            Text(vm.commandAssistantError ?? "")
        }
        .sheet(isPresented: $showingSnippetPalette) {
            SnippetPaletteSheet(
                snippets: availableSnippets,
                onInsert: { snippet in
                    vm.inputText += snippet.body
                    showingSnippetPalette = false
                },
                onDismiss: { showingSnippetPalette = false }
            )
        }
        .focusable()
    }

    // MARK: - Raw terminal content (TUI / alt-screen programs)

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
                HStack(spacing: 6) {
                    KeyboardAccessoryRail(ctrlLatched: $rawCtrlLatched) { bytes in
                        Task { try? await vm.activeShell?.send(bytes) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                    Button {
                        showRawHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(vm.commandHistory.isEmpty)
                }
                .conduitGlassChrome(cornerRadius: 16, interactive: true)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.bar)
            }
            .sheet(isPresented: $showRawHistory) {
                rawHistorySheet
            }
        } else {
            ProgressView("Opening terminal…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showRawHistory = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            StatusDot(isOk: vm.status == .connected)
            Text(statusLabel).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(vm.cwd)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1).truncationMode(.head)
                .foregroundStyle(.secondary)
            if case .failed = vm.status {
                Button { Task { await vm.reconnect() } } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.clear)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    private var statusLabel: String {
        switch vm.status {
        case .disconnected:        "disconnected"
        case .connecting:          "connecting…"
        case .connected:           "connected"
        case .suspended:           "suspended"
        case .reconnecting(let n): "reconnecting (\(n))"
        case .failed(let r):       "failed: \(r)"
        }
    }

    // MARK: - Reconnect banner

    private var reconnectBanner: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7)
            Text("Reconnecting…").font(.caption.weight(.medium))
            Spacer()
            Button("Cancel") { Task { await vm.disconnect() } }
                .font(.caption).buttonStyle(.bordered).controlSize(.mini)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.yellow.opacity(0.1))
    }

    // MARK: - Block scroll

    private var blockScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(vm.blocks.blocks) { block in
                        BlockRow(
                            block: block,
                            render: vm.blocks.render(block),
                            liveHandle: vm.blocks.liveBlockHandles[block.id],
                            onLiveBytes: { bytes in
                                Task { await vm.sendKeystrokes(Array(bytes)) }
                            },
                            onLiveResize: { cols, rows in
                                Task { await vm.resizeUnifiedPTY(cols: cols, rows: rows) }
                            }
                        ) {
                            explainText = ""
                            explainTarget = block
                        } onRerun: {
                            Task { await vm.rerun(block) }
                        } onCollapse: {
                            vm.blocks.toggleCollapsed(id: block.id)
                            Haptics.selection()
                        } onStar: {
                            vm.blocks.toggleStarred(id: block.id)
                            Haptics.selection()
                        } footer: {
                            if block.id == activeBlockID {
                                activeBlockInput
                            }
                        }
                        .id(block.id)
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .onChange(of: vm.blocks.blocks.count) { _, _ in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: vm.blocks.blocks.last?.chunks.count) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var activeBlockID: BlockID? {
        vm.blocks.blocks.last { block in
            switch block.state {
            case .done:
                return false
            case .promptEditing, .submitted, .executing:
                return true
            }
        }?.id
    }

    // MARK: - Active block input (Phase 4/5)
    //
    // • Prompt/idle mode: TerminalSafeTextField (fixed smart-dash / autocorrect)
    // • Executing mode:   LivePromptInputView + "live" indicator
    //   Every character the user presses goes directly to the PTY.
    //   Visual echo comes from the program's own PTY output in the active block.

    private var isExecuting: Bool {
        vm.isExecutingUnified
    }

    @ViewBuilder
    private var activeBlockInput: some View {
        Divider().padding(.vertical, 2)
        if isExecuting {
            executingComposer
        } else {
            promptComposer
        }
    }

    private var accessoryDock: some View {
        HStack(spacing: 6) {
            KeyboardAccessoryRail(ctrlLatched: $rawCtrlLatched) { bytes in
                Task { await vm.sendKeystrokes(bytes) }
            }
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            Button {
                showRawHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(vm.commandHistory.isEmpty)
        }
        .conduitGlassChrome(cornerRadius: 16, interactive: true)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Color.black.opacity(0.35)
                .background(.ultraThinMaterial)
        )
        .sheet(isPresented: $showRawHistory) {
            rawHistorySheet
        }
    }

    private var promptComposer: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(vm.inputText.hasPrefix("#") ? "#" : "$")
                .font(.system(.body, design: .monospaced).weight(.medium))
                .foregroundStyle(vm.inputText.hasPrefix("#") ? Color.accentColor : .secondary)

            // Phase 0.1: TerminalSafeTextField replaces SwiftUI TextField
            // to prevent -- → — and other smart-punctuation mutations.
            // autoFocus: true so the cursor is always visible when connected.
            TerminalSafeTextField(
                vm.isTranslating ? "translating…" : "command",
                text: $vm.inputText,
                isDisabled: vm.isTranslating,
                autoFocus: true
            ) {
                Task { await vm.submit() }
            }
            .frame(maxWidth: .infinity)

            Button {
                Task {
                    if dictation.isListening {
                        dictation.stop()
                    } else {
                        await dictation.start { text in
                            vm.inputText = text
                        }
                    }
                }
            } label: {
                Image(systemName: dictation.isListening ? "mic.fill" : "mic")
                    .font(.title2)
                    .foregroundStyle(dictation.isListening ? .red : .secondary)
            }
            Button { showingSnippetPalette = true } label: {
                Image(systemName: "chevron.up.square").font(.title2)
            }
            Button {
                Task { await vm.submit() }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .disabled(vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Executing-state composer — shows a "live" indicator and a
    /// `LivePromptInputView` that forwards every keystroke to the PTY.
    private var executingComposer: some View {
        HStack(alignment: .center, spacing: 8) {
            // Pulse indicator
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.green)

            // Tap anywhere on this row to bring up the keyboard.
            Button {
                liveInputActive = true
            } label: {
                Text("Running — tap to type")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Zero-size UIKeyInput view — all typing routes through here to PTY.
            LivePromptInputView(isActive: $liveInputActive) { bytes in
                Task { await vm.sendKeystrokes(bytes) }
            }
            .frame(width: 1, height: 1)

            Button {
                Task { await vm.sendKeystrokes([0x03]) }
            } label: {
                Image(systemName: "stop.circle").font(.title2)
            }
            .accessibilityLabel("Ctrl-C")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Phase 6: Tmux session sheet

    private var tmuxSessionSheet: some View {
        NavigationStack {
            List {
                Section("Available Sessions") {
                    ForEach(vm.availableTmuxSessions, id: \.self) { name in
                        Button {
                            vm.attachToTmuxSession(name)
                            showTmuxSheet = false
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.3.group")
                                    .foregroundStyle(.tint)
                                Text(name)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("Attach")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Tmux Sessions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { showTmuxSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
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
                            .background(.tertiary.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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

// MARK: - Block row

private struct BlockRow<Footer: View>: View {
    let block: Block
    let render: AttributedString
    let liveHandle: TerminalFeedHandle?
    let onLiveBytes: ((ArraySlice<UInt8>) -> Void)?
    let onLiveResize: ((Int, Int) -> Void)?
    let onExplain: () -> Void
    let onRerun: () -> Void
    let onCollapse: () -> Void
    let onStar: () -> Void
    let footer: Footer

    private var isFailed: Bool { block.exitStatus?.isSuccess == false }

    // Visually distinguish executing blocks with a subtle shimmer/border.
    private var isExecuting: Bool {
        block.state == .executing || block.state == .submitted
    }

    /// True when an inline TUI (Ink/claude) is live in this block.
    private var hasLiveTerminal: Bool {
        liveHandle != nil && block.state == .executing
    }

    /// Height for the embedded SwiftTerm view inside a live block.
    /// Scales with screen height (≈55%, clamped 360–720) so phones, large
    /// phones, and iPads each get a sensible window into the running TUI.
    /// SwiftTerm's `sizeChanged` then fires `onLiveResize` to SIGWINCH the
    /// remote process to match this height in rows.
    private var inlineTerminalHeight: CGFloat {
        #if os(iOS)
        let screenHeight = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.height ?? 844
        return min(720, max(360, screenHeight * 0.55))
        #else
        return 420
        #endif
    }

    var body: some View {
        HStack(spacing: 0) {
            if isFailed {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.red).frame(width: 3).padding(.vertical, 4)
            } else if isExecuting {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.green.opacity(0.8)).frame(width: 3).padding(.vertical, 4)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    PromptLine(hostName: block.prompt.hostName, cwd: block.prompt.cwd)
                    // Show exit chip only for finished blocks
                    if let status = block.exitStatus { ExitChip(code: status.code) }
                    if let d = block.duration {
                        Text(String(format: "%.2fs", d))
                            .font(.caption2.monospaced()).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if isExecuting {
                        ProgressView().scaleEffect(0.6)
                    }
                    if block.isStarred {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                    }
                    Button(action: onCollapse) {
                        Image(systemName: block.isCollapsed ? "chevron.down" : "chevron.up")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                // Show command only if we have one (empty during early promptEditing)
                if !block.command.isEmpty {
                    Text(block.command)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                if !block.isCollapsed {
                    if hasLiveTerminal, let handle = liveHandle {
                        // Warp-style: the active executing block hosts the
                        // live SwiftTerm grid in place of static text. Bytes
                        // arrive through `handle.yield(_:)` from
                        // SessionViewModel.onBlockBytes; keystrokes flow back
                        // out via `onLiveBytes` to vm.sendKeystrokes.
                        RawTerminalView(
                            feedHandle: handle,
                            onUserBytes: { bytes in onLiveBytes?(bytes) },
                            onResize: { cols, rows in onLiveResize?(cols, rows) },
                            inlineEmbedded: true
                        )
                        .frame(height: inlineTerminalHeight)
                        .frame(maxWidth: .infinity)
                    } else if block.hasOutput {
                        Text(render)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                footer
            }
            .padding(12)
        }
        .background(
            ZStack {
                // Dark translucent card — Warp-style.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                if isFailed {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.red.opacity(0.06))
                }
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contextMenu {
            // Phase Q3: rerun + explain disabled while executing
            if !isExecuting {
                Button { onRerun() } label: { Label("Re-run", systemImage: "arrow.clockwise") }
            }
            Button { onStar() } label: {
                Label(block.isStarred ? "Unstar" : "Star",
                      systemImage: block.isStarred ? "star.slash" : "star")
            }
            Button {
                #if os(iOS)
                UIPasteboard.general.string = block.command
                #endif
            } label: { Label("Copy command", systemImage: "doc.on.doc") }
            if block.hasOutput {
                Button {
                    #if os(iOS)
                    UIPasteboard.general.string = block.joinedOutput
                    #endif
                } label: { Label("Copy output", systemImage: "doc.on.clipboard") }
            }
            if !isExecuting, block.exitStatus?.isSuccess == false {
                Divider()
                Button { onExplain() } label: { Label("Explain with AI", systemImage: "sparkles") }
            }
        }
    }

    init(
        block: Block,
        render: AttributedString,
        liveHandle: TerminalFeedHandle? = nil,
        onLiveBytes: ((ArraySlice<UInt8>) -> Void)? = nil,
        onLiveResize: ((Int, Int) -> Void)? = nil,
        onExplain: @escaping () -> Void,
        onRerun: @escaping () -> Void,
        onCollapse: @escaping () -> Void,
        onStar: @escaping () -> Void,
        @ViewBuilder footer: () -> Footer
    ) {
        self.block = block
        self.render = render
        self.liveHandle = liveHandle
        self.onLiveBytes = onLiveBytes
        self.onLiveResize = onLiveResize
        self.onExplain = onExplain
        self.onRerun = onRerun
        self.onCollapse = onCollapse
        self.onStar = onStar
        self.footer = footer()
    }
}

#endif
