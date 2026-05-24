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
    @FocusState private var composerFocused: Bool
    @State private var showingSnippetPalette = false
    @State private var availableSnippets: [Snippet] = []

    public init(viewModel: SessionViewModel) {
        _vm = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            if vm.isRaw {
                rawTerminalContent
            } else {
                blockScroll
                Divider()
                composer
            }
        }
        .navigationTitle(vm.host.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await vm.connect()
            if let db = try? AppDatabase.openShared(),
               let snippets = try? await SnippetRepository(db: db).all() {
                availableSnippets = snippets
            }
        }
        .sheet(item: $explainTarget) { block in explainSheet(block: block) }
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

    // MARK: - Raw terminal content (M2)

    @ViewBuilder
    private var rawTerminalContent: some View {
        if let handle = vm.rawFeedHandle {
            RawTerminalView(
                feedHandle: handle,
                onUserBytes: { _ in
                    // User bytes from SwiftTerm's own keyboard handling are
                    // forwarded to the shell directly. The keyboard rail
                    // goes via onBytes below.
                },
                onResize: { cols, rows in
                    Task { try? await vm.activeShell?.resize(cols: cols, rows: rows) }
                }
            )
            .ignoresSafeArea()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                KeyboardAccessoryRail { bytes in
                    Task { try? await vm.activeShell?.send(bytes) }
                }
                .frame(height: 44)
            }
        } else {
            // Handle not yet available — show a loading indicator.
            ProgressView("Opening terminal…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.thinMaterial)
    }

    private var statusLabel: String {
        switch vm.status {
        case .disconnected:       "disconnected"
        case .connecting:         "connecting…"
        case .connected:          "connected"
        case .suspended:          "suspended"
        case .reconnecting(let n): "reconnecting (\(n))"
        case .failed(let r):      "failed: \(r)"
        }
    }

    // MARK: - Block scroll

    private var blockScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(vm.blocks.blocks) { block in
                        BlockRow(block: block, render: vm.blocks.render(block)) {
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

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(vm.inputText.hasPrefix("#") ? "#" : "$")
                .font(.system(.body, design: .monospaced).weight(.medium))
                .foregroundStyle(vm.inputText.hasPrefix("#") ? Color.accentColor : .secondary)
            TextField(
                vm.isTranslating ? "translating…" : "command",
                text: $vm.inputText,
                axis: .horizontal
            )
            .focused($composerFocused)
            .font(.system(.body, design: .monospaced))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.send)
            .disabled(vm.isTranslating)
            .onSubmit { Task { await vm.submit() } }

            Button { showingSnippetPalette = true } label: {
                Image(systemName: "chevron.up.square")
                    .font(.title2)
            }
            Button {
                Task { await vm.submit() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
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
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !isExplaining {
                        Button {
                            Task { await runExplain(block: block) }
                        } label: {
                            Label(explainText.isEmpty ? "Explain" : "Explain again",
                                  systemImage: "sparkles")
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
}

// MARK: - Block row

private struct BlockRow: View {
    let block: Block
    let render: AttributedString
    let onExplain: () -> Void
    let onRerun: () -> Void
    let onCollapse: () -> Void
    let onStar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                PromptLine(hostName: block.prompt.hostName, cwd: block.prompt.cwd)
                if let status = block.exitStatus { ExitChip(code: status.code) }
                if let d = block.duration {
                    Text(String(format: "%.2fs", d))
                        .font(.caption2.monospaced()).foregroundStyle(.tertiary)
                }
                Spacer()
                if block.isStarred {
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                }
                Button(action: onCollapse) {
                    Image(systemName: block.isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Text(block.command)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            if !block.isCollapsed, block.hasOutput {
                Text(render)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            Button { onRerun() } label: { Label("Re-run", systemImage: "arrow.clockwise") }
            Button { onStar() } label: {
                Label(block.isStarred ? "Unstar" : "Star", systemImage: block.isStarred ? "star.slash" : "star")
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
            if block.exitStatus?.isSuccess == false {
                Divider()
                Button { onExplain() } label: { Label("Explain with AI", systemImage: "sparkles") }
            }
        }
    }
}

#endif
