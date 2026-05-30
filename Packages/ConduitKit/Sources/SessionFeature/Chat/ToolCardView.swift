#if os(iOS)
import SwiftUI
import ConduitCore
import TerminalEngine
import DesignSystem

// Maps a Block onto a chat-style tool card.
// State: promptEditing/submitted → none/queued, executing → running (animated),
//        done(0) → success, done(≠0) → error.

public struct ToolCardView<Footer: View>: View {
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

    @State private var searchActive = false
    @State private var searchQuery = ""
    @State private var runningPhase = false

    @AppStorage("terminalFontSize") private var termFontSize: Double = 11
    @Environment(\.conduitTokens) private var t

    public init(
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

    // MARK: - Derived state

    private var cardState: ToolCardState {
        switch block.state {
        case .promptEditing: return .idle
        case .submitted:     return .queued
        case .executing:     return .running
        case .done(let code): return code == 0 ? .success : .error(code: code)
        }
    }

    private var hasLiveTerminal: Bool {
        liveHandle != nil && block.state == .executing
    }

    private var inlineTerminalHeight: CGFloat {
        #if os(iOS)
        let screenH = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.height ?? 844
        return min(720, max(360, screenH * 0.55))
        #else
        return 420
        #endif
    }

    private var highlightedRender: AttributedString {
        guard !searchQuery.isEmpty,
              let result = BlockSearch.search(query: searchQuery, in: block),
              !result.ranges.isEmpty else { return render }
        var attr = AttributedString(block.joinedOutput)
        for range in result.ranges {
            if let attrRange = Range(range, in: attr) {
                attr[attrRange].backgroundColor = .init(.systemYellow.withAlphaComponent(0.35))
                attr[attrRange].foregroundColor  = .init(.label)
            }
        }
        return attr
    }

    // MARK: - Body

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // ── Left gutter accent by state (matches DSBlockCard) ──────────
            Rectangle()
                .fill(gutterColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 0) {
                // ── Tier 1: kind label + meta (on card surface) ───────────
                cardHeader
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)

                if !block.isCollapsed {
                    // ── Tier 2: "$ command" bar (sunken) ──────────────────
                    commandBar

                    // ── Tier 3: output panel (darkest terminal surface) ───
                    if showsOutputArea {
                        outputBody
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(t.termBg)
                    }

                    // ── Search bar ────────────────────────────────────────
                    if searchActive {
                        searchBar.padding(.horizontal, 12).padding(.vertical, 6)
                    }

                    // ── Caller-injected footer (prompt input) ─────────────
                    if hasFooter {
                        Rectangle().fill(t.termBorder).frame(height: 1)
                        footer.padding(.horizontal, 12).padding(.vertical, 4)
                    }
                }
            }
        }
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 0.75)
        )
        .contextMenu { contextMenuItems }
        .onAppear {
            if cardState == .running {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    runningPhase = true
                }
            }
        }
        .onChange(of: cardState == .running) { _, isRunning in
            if isRunning {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    runningPhase = true
                }
            } else {
                runningPhase = false
            }
        }
    }

    // MARK: - Card header

    private var cardHeader: some View {
        HStack(spacing: 8) {
            // Kind label — "RUN › COMMAND" (verb › noun, matches tc2 design)
            HStack(spacing: 4) {
                Text(kind.verb).foregroundStyle(t.termText2).fontWeight(.semibold)
                Text("›").foregroundStyle(t.termText3)
                Text(kind.noun).foregroundStyle(t.termText3)
            }
            .font(.dsMonoPt(10))
            .tracking(10 * 0.12)
            .textCase(.uppercase)

            Spacer(minLength: 8)

            // Meta cluster
            if block.originatingSnippetID != nil {
                Image(systemName: "curlybraces.square.fill")
                    .font(.caption2).foregroundStyle(t.termAccent)
            }
            if let d = block.duration, cardState != .running {
                Text(String(format: "%.2fs", d))
                    .font(.dsMonoPt(11)).foregroundStyle(t.termText3)
            }
            if case .done(let code) = block.state {
                DSExitChip(code: code)
            }
            if cardState == .running {
                ProgressView().scaleEffect(0.5).tint(t.termAccent).frame(width: 12, height: 12)
            }
            if block.isStarred {
                Image(systemName: "star.fill").font(.caption2).foregroundStyle(t.termAccent)
            }
            Button(action: onCollapse) {
                Image(systemName: block.isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.caption2).foregroundStyle(t.termText3)
            }
            .buttonStyle(.plain)
        }
    }

    /// The "$ command" bar — terminal prompt (reused `DSPromptLine`) + the
    /// command, on a sunken surface between the header and the output panel.
    private var commandBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            DSPromptLine(host: block.prompt.hostName, cwd: block.prompt.cwd)
                .lineLimit(1)
            if !block.command.isEmpty {
                Text(block.command)
                    .font(.dsMonoPt(termFontSize))
                    .foregroundStyle(t.termText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.termSurface2)
        .overlay(alignment: .top) { Rectangle().fill(t.termBorder).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(t.termBorder).frame(height: 1) }
    }

    /// Kind verb/noun. Shell blocks are always "Run › command"; richer kinds
    /// (Read/Apply/Write) arrive with agent tool cards (Phase 3).
    private var kind: (verb: String, noun: String) {
        ("Run", "command")
    }

    private var showsOutputArea: Bool {
        hasLiveTerminal || block.hasOutput || cardState == .running
    }

    // MARK: - Output body

    @ViewBuilder
    private var outputBody: some View {
        if hasLiveTerminal, let handle = liveHandle {
            RawTerminalView(
                feedHandle: handle,
                onUserBytes: { bytes in onLiveBytes?(bytes) },
                onResize: { cols, rows in onLiveResize?(cols, rows) },
                inlineEmbedded: true
            )
            .frame(height: inlineTerminalHeight)
            .frame(maxWidth: .infinity)
        } else if block.hasOutput {
            Text(searchQuery.isEmpty ? render : highlightedRender)
                .font(.dsMonoPt(termFontSize))
                .foregroundStyle(t.termText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if cardState == .running {
            // Placeholder streaming caret while output hasn't arrived yet
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(t.termAccent)
                    .frame(width: 2, height: 14)
                    .opacity(runningPhase ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(), value: runningPhase)
                Text("Running…")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.termText3)
            }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(t.termText3)
            TextField("Search output…", text: $searchQuery)
                .font(.dsMonoPt(termFontSize))
                .foregroundStyle(t.termText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if let result = BlockSearch.search(query: searchQuery, in: block) {
                Text("\(result.matchCount) match\(result.matchCount == 1 ? "" : "es")")
                    .font(.caption2).foregroundStyle(t.termAccent)
            } else if !searchQuery.isEmpty {
                Text("No matches").font(.caption2).foregroundStyle(t.termText3)
            }
            Button { searchActive = false; searchQuery = "" } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(t.termText3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(t.termSurface2.cornerRadius(6))
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        if cardState != .running {
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
            Divider()
            Button {
                withAnimation { searchActive.toggle() }
                if !searchActive { searchQuery = "" }
            } label: {
                Label(searchActive ? "Hide search" : "Search output",
                      systemImage: searchActive ? "magnifyingglass.circle.fill" : "magnifyingglass")
            }
        }
        if cardState != .running, case .error = cardState {
            Divider()
            Button { onExplain() } label: { Label("Explain with AI", systemImage: "sparkles") }
        }
    }

    // MARK: - Card chrome

    private var gutterColor: Color {
        switch cardState {
        case .success: return t.termOk.opacity(0.55)
        case .error:   return t.termErr
        case .running: return t.termAccent
        case .queued:  return t.termText3
        case .idle:    return t.termText3
        }
    }

    private var cardBg: Color {
        t.termSurface
    }

    private var cardBorder: Color {
        switch cardState {
        case .running: return t.termAccent.opacity(0.4)
        case .error:   return t.termErr.opacity(0.4)
        default:       return t.termBorder
        }
    }

    private var hasFooter: Bool { Footer.self != EmptyView.self }
}

// MARK: - Card state

private enum ToolCardState: Equatable {
    case idle
    case queued
    case running
    case success
    case error(code: Int)
}

#endif
