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
    @State private var liveInputActive = false
    @State private var tickHistory: [Double] = []
    @State private var showConnectOverlay = false
    @State private var connectOverlayPhase: SSHConnectPhase = .connecting

    @Environment(\.conduitTokens) private var t

    public init(viewModel: SessionViewModel) {
        _vm = State(initialValue: viewModel)
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
    }

    // MARK: - Core view (split to keep body type-checkable)

    private var coreView: some View {
        ZStack {
            t.surf0.ignoresSafeArea()

            VStack(spacing: 0) {
                // Always-dark HUD strip
                AgentStatusBar(
                    state: agentState,
                    message: agentMessage,
                    pendingApprovals: 0,
                    tickValues: tickHistory
                )

                // Compact identity header below HUD
                ChatHeaderView(
                    hostName: vm.host.name,
                    cwd: vm.cwd,
                    state: agentState
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
                        }
                    )
                }
            }

            // SSH connect orb overlay — stays visible briefly after connection
            if showConnectOverlay {
                SSHConnectOverlay(phase: connectOverlayPhase)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if connectOverlayPhase == .connected {
                            withAnimation(.easeOut(duration: 0.35)) { showConnectOverlay = false }
                        }
                    }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !vm.isRaw {
                chatBottomBar
            }
        }
        .toolbar {
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
        .sheet(isPresented: $showTmuxSheet) {
            tmuxSessionSheet
        }
        .task {
            if let db = try? AppDatabase.openShared(),
               let snippets = try? await SnippetRepository(db: db).rankedForPalette() {
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

    private var agentMessage: String? {
        switch vm.status {
        case .failed(let reason): return reason
        case .reconnecting(let n): return "attempt \(n)"
        default: return nil
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
        .sheet(isPresented: $showRawHistory) { rawHistorySheet }
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
                HStack(spacing: 6) {
                    KeyboardAccessoryRail(ctrlLatched: $rawCtrlLatched) { bytes in
                        Task { try? await vm.activeShell?.send(bytes) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                    Button { showRawHistory = true } label: {
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
        NavigationStack {
            List {
                Section("Available Sessions") {
                    ForEach(vm.availableTmuxSessions, id: \.self) { name in
                        Button {
                            vm.attachToTmuxSession(name)
                            showTmuxSheet = false
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.3.group").foregroundStyle(.tint)
                                Text(name).font(.system(.body, design: .monospaced)).foregroundStyle(.primary)
                                Spacer()
                                Text("Attach").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Tmux Sessions")
            .navigationBarTitleDisplayMode(.inline)
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

#endif
