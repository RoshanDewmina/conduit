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
        VStack(alignment: .leading, spacing: 0) {
            // ── Top state strip (matches tc2 design) ──────────────────────
            Rectangle()
                .fill(stripColor)
                .frame(height: 3)

            // ── Header strip ──────────────────────────────────────────────
            cardHeader
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, block.isCollapsed ? 10 : 6)

            if !block.isCollapsed {
                Divider().opacity(0.5)
                    .padding(.horizontal, 12)

                // ── Output body ───────────────────────────────────────────
                outputBody
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)

                // ── Search bar ────────────────────────────────────────────
                if searchActive { searchBar.padding(.horizontal, 12).padding(.bottom, 6) }

                // ── Caller-injected footer (prompt input) ─────────────────
                if hasFooter {
                    Divider().opacity(0.4).padding(.horizontal, 12)
                    footer.padding(.horizontal, 12).padding(.vertical, 4)
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
        HStack(alignment: .center, spacing: 8) {
            // State icon / spinner
            stateIcon

            VStack(alignment: .leading, spacing: 2) {
                // Command
                if !block.command.isEmpty {
                    Text(block.command)
                        .font(.system(.callout, design: .monospaced).weight(.medium))
                        .foregroundStyle(t.text1)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                // Prompt line (host:cwd)
                HStack(spacing: 4) {
                    Text(block.prompt.hostName).foregroundStyle(t.accent).font(.caption2)
                    Text(":").foregroundStyle(t.text4).font(.caption2)
                    Text(block.prompt.cwd)
                        .foregroundStyle(t.text3)
                        .font(.caption2.monospaced())
                        .lineLimit(1).truncationMode(.head)
                }
            }

            Spacer()

            // Right meta cluster
            HStack(spacing: 6) {
                if block.originatingSnippetID != nil {
                    Image(systemName: "curlybraces.square.fill")
                        .font(.caption2).foregroundStyle(t.accent)
                }
                if let d = block.duration, cardState != .running {
                    Text(String(format: "%.2fs", d))
                        .font(.caption2.monospaced()).foregroundStyle(t.text4)
                }
                if case .error(let code) = cardState {
                    DSChip("\(code)", tone: .danger, style: .soft)
                } else if case .success = cardState, block.exitStatus != nil {
                    Image(systemName: "checkmark").font(.caption2.weight(.semibold))
                        .foregroundStyle(t.ok)
                }
                if block.isStarred {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(t.warn)
                }
                Button(action: onCollapse) {
                    Image(systemName: block.isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.caption2).foregroundStyle(t.text3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var stateIcon: some View {
        ZStack {
            switch cardState {
            case .idle:
                Circle().fill(t.text4.opacity(0.3)).frame(width: 22, height: 22)
                Image(systemName: "terminal").font(.caption2).foregroundStyle(t.text3)
            case .queued:
                Circle().fill(t.info.opacity(0.15)).frame(width: 22, height: 22)
                Image(systemName: "clock").font(.caption2).foregroundStyle(t.info)
            case .running:
                Circle()
                    .fill(t.accent.opacity(runningPhase ? 0.25 : 0.12))
                    .frame(width: 22, height: 22)
                ProgressView().scaleEffect(0.55).tint(t.accent)
            case .success:
                Circle().fill(t.ok.opacity(0.15)).frame(width: 22, height: 22)
                Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(t.ok)
            case .error:
                Circle().fill(t.danger.opacity(0.15)).frame(width: 22, height: 22)
                Image(systemName: "xmark").font(.caption2.weight(.bold)).foregroundStyle(t.danger)
            }
        }
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
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(t.text2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        } else if cardState == .running {
            // Placeholder streaming caret while output hasn't arrived yet
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(t.accent)
                    .frame(width: 2, height: 14)
                    .opacity(runningPhase ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(), value: runningPhase)
                Text("Running…")
                    .font(.caption.monospaced())
                    .foregroundStyle(t.text3)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(t.text3)
            TextField("Search output…", text: $searchQuery)
                .font(.caption.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if let result = BlockSearch.search(query: searchQuery, in: block) {
                Text("\(result.matchCount) match\(result.matchCount == 1 ? "" : "es")")
                    .font(.caption2).foregroundStyle(t.accent)
            } else if !searchQuery.isEmpty {
                Text("No matches").font(.caption2).foregroundStyle(t.text3)
            }
            Button { searchActive = false; searchQuery = "" } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(t.text3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(t.surf2.cornerRadius(6))
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

    private var stripColor: Color {
        switch cardState {
        case .success: return t.ok
        case .error:   return t.danger
        case .running: return t.accent
        case .queued:  return t.info
        case .idle:    return t.text4.opacity(0.5)
        }
    }

    private var cardBg: Color {
        switch cardState {
        case .running: return t.surf1
        case .error:   return t.danger.opacity(0.05)
        default:       return t.surf1
        }
    }

    private var cardBorder: Color {
        switch cardState {
        case .running: return t.accent.opacity(0.35)
        case .error:   return t.danger.opacity(0.25)
        case .success: return t.ok.opacity(0.2)
        default:       return t.surf3
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
