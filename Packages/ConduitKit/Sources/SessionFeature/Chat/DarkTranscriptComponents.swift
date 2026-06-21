#if os(iOS)
import SwiftUI
import DesignSystem

// Shared transcript components. Terminal blocks retain the intentionally-dark
// terminal palette, while surrounding chat chrome follows the selected app theme.

// MARK: - User bubble (right-aligned orange)

public struct DarkUserBubble: View {
    private let text: String
    @Environment(\.conduitTokens) private var t

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
    @Environment(\.conduitTokens) private var t

    public init(_ text: String) { self.text = text }

    public var body: some View {
        HStack(alignment: .top) {
            Text(text)
                .font(.dsSansPt(16))
                .foregroundStyle(t.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(t.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(t.border.opacity(0.6), lineWidth: 1)
                )
            Spacer(minLength: 56)
        }
    }
}

// MARK: - Typing indicator (the agent is working)
//
// Replaces the old pixel-grid + "thinking…/streaming" label. A calm row of three
// dots that breathe in a gentle stagger, inside an assistant-bubble surface — it
// reads as "composing a reply" and morphs into the real reply when text arrives.
// Designed to be quiet enough to watch for a long run.

public struct DarkTypingIndicator: View {
    @Environment(\.conduitTokens) private var t
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
    public enum State { case running, done, error }

    private let host: String
    private let command: String?
    private let output: String
    private let state: State

    /// Lines kept visible while collapsed.
    private let collapsedLineCount = 8

    @State private var expanded = false
    @Environment(\.conduitTokens) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(host: String, command: String?, output: String, state: State) {
        self.host = host
        self.command = command
        self.output = output
        self.state = state
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
            withAnimation(ConduitMotion.resolved(.smooth(duration: 0.26, extraBounce: 0), reduceMotion: reduceMotion)) {
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
            Circle().fill(Color(red: 0.86, green: 0.45, blue: 0.30)).frame(width: 9, height: 9)
            Circle().fill(t.termText3.opacity(0.55)).frame(width: 9, height: 9)
            Circle().fill(t.termText3.opacity(0.35)).frame(width: 9, height: 9)
            Text("zsh — \(host)")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.termText3)
                .padding(.leading, 4)
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
    @Environment(\.conduitTokens) private var t

    public init(
        title: String,
        subtitle: String?,
        isLive: Bool,
        onBack: @escaping () -> Void,
        onWorkspace: @escaping () -> Void,
        onNew: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isLive = isLive
        self.onBack = onBack
        self.onWorkspace = onWorkspace
        self.onNew = onNew
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
            Spacer(minLength: 8)
            if isLive {
                HStack(spacing: 5) {
                    Circle().fill(t.ok).frame(width: 7, height: 7)
                    Text("live").font(.dsMonoPt(11, weight: .medium)).foregroundStyle(t.ok)
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(t.okSoft, in: Capsule())
            }
            DSCircleButton("square.grid.2x2", diameter: 38, accessibilityLabel: "Open workspace", action: onWorkspace)
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
