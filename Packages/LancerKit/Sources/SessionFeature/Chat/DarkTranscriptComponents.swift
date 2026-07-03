#if os(iOS)
import SwiftUI
import UIKit
import DesignSystem

// Shared transcript components. Terminal blocks retain the intentionally-dark
// terminal palette, while surrounding chat chrome follows the selected app theme.

// MARK: - User bubble (right-aligned orange)

public struct DarkUserBubble: View {
    private let text: String
    @Environment(\.lancerTokens) private var t

    public init(_ text: String) { self.text = text }

    public var body: some View {
        HStack(alignment: .top) {
            Spacer(minLength: 56)
            Text(text)
                .font(.dsSansPt(16))
                .foregroundStyle(t.accentFg)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(t.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

// MARK: - Assistant prose bubble (left-aligned, neutral surface)
//
// The agent's natural-language reply. Mirrors DarkUserBubble's geometry but on a
// neutral surface and left-aligned — terminal/command output gets the dark
// DarkTerminalBlockCard instead, so prose never wears the macOS-window chrome.

public struct DarkAssistantBubble: View {
    private let text: String
    private let author: String?
    @State private var copied = false
    @Environment(\.lancerTokens) private var t

    public init(_ text: String, author: String? = nil) {
        self.text = text
        self.author = author
    }

    public var body: some View {
        // Assistant content renders full-width (Claude/ChatGPT style) so markdown
        // prose and fenced code cards have room — only user turns wear a bubble. A
        // small author row gives the reply clear authorship (the user bubble already
        // reads as "you" via its accent fill).
        VStack(alignment: .leading, spacing: 8) {
            if let author {
                HStack(spacing: 6) {
                    Circle().fill(t.accent).frame(width: 6, height: 6)
                    Text(author)
                        .font(.dsMonoPt(11, weight: .semibold))
                        .tracking(0.3)
                        .foregroundStyle(t.text3)
                }
            }
            MarkdownText(text, textColor: t.text)
            copyButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button {
                UIPasteboard.general.string = text
                Haptics.success()
            } label: { Label("Copy message", systemImage: "doc.on.doc") }
        }
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = text
            Haptics.success()
            withAnimation { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                await MainActor.run { withAnimation { copied = false } }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                Text(copied ? "Copied" : "Copy")
                    .font(.dsMonoPt(10.5, weight: .medium))
            }
            .foregroundStyle(copied ? t.ok : t.text4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy message")
    }
}

// MARK: - Typing indicator (the agent is working)
//
// Replaces the old pixel-grid + "thinking…/streaming" label. A calm row of three
// dots that breathe in a gentle stagger, inside an assistant-bubble surface — it
// reads as "composing a reply" and morphs into the real reply when text arrives.
// Designed to be quiet enough to watch for a long run.

public struct DarkTypingIndicator: View {
    @Environment(\.lancerTokens) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0.0

    public init() {}

    public var body: some View {
        HStack(alignment: .top) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(t.text3)
                        .frame(width: 7, height: 7)
                        .opacity(dotOpacity(i))
                        .scaleEffect(dotScale(i))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(t.border.opacity(0.6), lineWidth: 1)
            )
            .accessibilityLabel("Agent is working")
            Spacer(minLength: 56)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                phase = 1.0
            }
        }
    }

    // Each dot is offset in the cycle so the row "breathes" left-to-right.
    private func dotOpacity(_ i: Int) -> Double {
        let shifted = (phase + Double(i) * 0.22).truncatingRemainder(dividingBy: 1.0)
        return 0.35 + 0.55 * (0.5 - abs(shifted - 0.5)) * 2
    }

    private func dotScale(_ i: Int) -> Double {
        let shifted = (phase + Double(i) * 0.22).truncatingRemainder(dividingBy: 1.0)
        return 0.85 + 0.25 * (0.5 - abs(shifted - 0.5)) * 2
    }
}

// MARK: - Terminal block card (dark, traffic-light header + mono body)
//
// Collapsed by default — caps the body to the last few lines and a fixed height so
// a long command's scrollback doesn't dominate the transcript. Tap anywhere to
// expand to the full, scrollable output; tap again to re-collapse.

public struct DarkTerminalBlockCard: View {
    // Named `CardState`, not `State` — a nested `State` shadows SwiftUI's
    // `@State` property-wrapper attribute for every property below it in
    // this type, which Xcode 27/Swift 6.4 silently resolves correctly but
    // Xcode 26's Swift 6.2 compiler rejects outright ("enum 'State' cannot
    // be used as an attribute") — this only surfaces once CI is actually
    // able to compile the package under 6.2 (see the swift-tools-version
    // fix in the same change).
    public enum CardState { case running, done, error }

    private let host: String
    private let command: String?
    private let output: String
    private let state: CardState
    /// Whether this card is genuinely showing a shell/zsh invocation. When false,
    /// the header drops the "zsh — host" window-chrome claim and traffic-light
    /// dots — callers use this for non-shell tool calls (Read/Write/Edit/etc.) and
    /// plain error output that never touched a shell, so the card never implies a
    /// live terminal session that isn't real.
    private let isShellSession: Bool

    /// Lines kept visible while collapsed.
    private let collapsedLineCount = 8

    @State private var expanded = false
    @Environment(\.lancerTokens) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(host: String, command: String?, output: String, state: CardState, isShellSession: Bool = true) {
        self.host = host
        self.command = command
        self.output = output
        self.state = state
        self.isShellSession = isShellSession
    }

    /// Whether a tool name denotes a genuine shell/bash invocation, matching the
    /// same normalization the daemon uses (`daemon/lancerd/hook.go`'s tool-kind
    /// switch: "bash"/"Bash"/"shell"/"command" all mean the same thing across
    /// Claude Code/Codex/OpenCode/Kimi). Callers use this to decide whether a tool
    /// block earns terminal-window chrome, or renders as a plain tool call.
    public static func isShellToolName(_ toolName: String) -> Bool {
        switch toolName.lowercased() {
        case "bash", "shell", "command": return true
        default: return false
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            body(for: expanded ? outputLines : Array(outputLines.suffix(collapsedLineCount)))
        }
        .background(t.termBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(state == .error ? t.danger.opacity(0.4) : t.termText3.opacity(0.18), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            guard isExpandable else { return }
            Haptics.selection()
            withAnimation(LancerMotion.resolved(.smooth(duration: 0.26, extraBounce: 0), reduceMotion: reduceMotion)) {
                expanded.toggle()
            }
        }
        .accessibilityAddTraits(isExpandable ? .isButton : [])
        .accessibilityHint(isExpandable ? (expanded ? "Collapse output" : "Expand full output") : "")
    }

    /// More lines than the collapsed cap fit — only then is tapping meaningful.
    private var isExpandable: Bool { outputLines.count > collapsedLineCount }

    private var header: some View {
        HStack(spacing: 7) {
            if isShellSession {
                Circle().fill(t.termPrompt).frame(width: 9, height: 9)
                Circle().fill(t.termText3.opacity(0.55)).frame(width: 9, height: 9)
                Circle().fill(t.termText3.opacity(0.35)).frame(width: 9, height: 9)
            }
            Text(isShellSession ? "zsh — \(host)" : host)
                .font(.dsMonoPt(11))
                .foregroundStyle(t.termText3)
                .padding(.leading, isShellSession ? 4 : 0)
            Spacer(minLength: 0)
            if state == .error {
                Text("ERROR")
                    .font(.dsMonoPt(9.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(t.danger)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(t.danger.opacity(0.16), in: Capsule())
            }
            if isExpandable {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(t.termText3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(t.termSurface2)
    }

    @ViewBuilder
    private func body(for lines: [Line]) -> some View {
        let content = VStack(alignment: .leading, spacing: 3) {
            if let command, !command.isEmpty {
                Text("→ \(command)")
                    .foregroundStyle(t.termAccent)
            }
            if isExpandable && !expanded {
                Text("… \(outputLines.count - collapsedLineCount) earlier lines — tap to expand")
                    .font(.dsMonoPt(10.5))
                    .foregroundStyle(t.termText3.opacity(0.8))
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.text)
                    .foregroundStyle(line.color)
            }
        }
        .font(.dsMonoPt(12.5))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)

        if expanded {
            ScrollView { content }
                .frame(maxHeight: 420)
        } else {
            content
        }
    }

    private struct Line { let text: String; let color: Color }

    private var outputLines: [Line] {
        output.split(separator: "\n", omittingEmptySubsequences: false).map { raw in
            let s = String(raw)
            let lower = s.lowercased()
            let color: Color
            if state == .error || lower.contains("fail") || lower.contains("error") {
                color = t.danger
            } else if lower.hasPrefix("pass") || lower.contains(" pass") || lower.contains("✓") {
                color = t.termOk
            } else if s.hasPrefix("→") || s.hasPrefix("$") {
                color = t.termAccent
            } else {
                color = t.termText2
            }
            return Line(text: s, color: color)
        }
    }
}

// MARK: - Transcript header

public struct DarkTranscriptHeader: View {
    private let title: String
    private let subtitle: String?
    private let isLive: Bool
    private let onBack: () -> Void
    private let onWorkspace: () -> Void
    private let onNew: (() -> Void)?
    /// When non-nil, a Share button exports this transcript as text. Computed
    /// lazily by the caller so it reflects the turns at tap time.
    private let shareText: (() -> String)?
    /// When non-nil, shows a dedicated "Terminal & files" affordance that explains
    /// those SSH-only features and offers to connect this machine directly.
    private let onSSHFeatures: (() -> Void)?
    /// When non-nil, adds an "Import to Lancer" overflow-menu item that turns
    /// this terminal-originated Observed Session into a durable, cross-device
    /// Lancer conversation (see `ObservedSessionView`).
    private let onImportToLancer: (() -> Void)?
    @Environment(\.lancerTokens) private var t

    public init(
        title: String,
        subtitle: String?,
        isLive: Bool,
        onBack: @escaping () -> Void,
        onWorkspace: @escaping () -> Void,
        onNew: (() -> Void)? = nil,
        shareText: (() -> String)? = nil,
        onSSHFeatures: (() -> Void)? = nil,
        onImportToLancer: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isLive = isLive
        self.onBack = onBack
        self.onWorkspace = onWorkspace
        self.onNew = onNew
        self.shareText = shareText
        self.onSSHFeatures = onSSHFeatures
        self.onImportToLancer = onImportToLancer
    }

    public var body: some View {
        HStack(spacing: 12) {
            DSCircleButton("chevron.left", diameter: 38, accessibilityLabel: "Back", action: onBack)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.dsDisplayPt(19, weight: .bold))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)   // the title/machine wins width over trailing chrome
            Spacer(minLength: 8)
            if isLive {
                HStack(spacing: 5) {
                    Circle().fill(t.ok).frame(width: 7, height: 7)
                    Text("live").font(.dsMonoPt(11, weight: .medium)).foregroundStyle(t.ok)
                }
                .fixedSize()   // never let the badge compress its label to two lines
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(t.okSoft, in: Capsule())
            }
            if let onSSHFeatures {
                Button(action: onSSHFeatures) {
                    Image(systemName: "terminal")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(t.text2)
                        .frame(width: 38, height: 38)
                        .background(t.surface2, in: Circle())
                }
                .accessibilityLabel("Terminal & files")
            }
            // Secondary actions (Share, Open workspace) live in an overflow menu so
            // they don't crowd the title into a "My mach…" truncation. Only the
            // primary New-thread action keeps a dedicated circle button.
            Menu {
                if let onImportToLancer {
                    Button { onImportToLancer() } label: {
                        Label("Import to Lancer", systemImage: "arrow.down.doc")
                    }
                }
                if let shareText {
                    ShareLink(item: shareText()) {
                        Label("Share transcript", systemImage: "square.and.arrow.up")
                    }
                }
                Button { onWorkspace() } label: {
                    Label("Open workspace", systemImage: "folder")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(t.text2)
                    .frame(width: 38, height: 38)
                    .background(t.surface2, in: Circle())
            }
            .accessibilityLabel("More actions")
            if let onNew {
                DSCircleButton("plus", diameter: 38, accessibilityLabel: "New thread", action: onNew)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}
#endif
