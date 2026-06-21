#if os(iOS)
import SwiftUI
import DesignSystem

// Shared dark "transcript thread" chat components (owner mockup A). Used by both
// the relay New Chat surface and the SSH session view so the two read identically.
// Everything here renders on the dark terminal palette (term* tokens) regardless
// of the app's light/dark theme — the chat is always dark by design.

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

// MARK: - Terminal block card (dark, traffic-light header + mono body)

public struct DarkTerminalBlockCard: View {
    public enum State { case running, done, error }

    private let host: String
    private let command: String?
    private let output: String
    private let state: State
    @Environment(\.conduitTokens) private var t

    public init(host: String, command: String?, output: String, state: State) {
        self.host = host
        self.command = command
        self.output = output
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title strip: 3 traffic lights + "zsh — host"
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(t.termSurface2)

            // Body: colored mono output
            VStack(alignment: .leading, spacing: 3) {
                if let command, !command.isEmpty {
                    Text("→ \(command)")
                        .foregroundStyle(t.termAccent)
                }
                ForEach(Array(outputLines.enumerated()), id: \.offset) { _, line in
                    Text(line.text)
                        .foregroundStyle(line.color)
                }
            }
            .font(.dsMonoPt(12.5))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .background(t.termBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(state == .error ? t.danger.opacity(0.4) : t.termText3.opacity(0.18), lineWidth: 1)
        )
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

// MARK: - Dark transcript header

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
                    .foregroundStyle(t.termText)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.termText3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if isLive {
                HStack(spacing: 5) {
                    Circle().fill(t.termOk).frame(width: 7, height: 7)
                    Text("live").font(.dsMonoPt(11, weight: .medium)).foregroundStyle(t.termOk)
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(t.termOk.opacity(0.14), in: Capsule())
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
