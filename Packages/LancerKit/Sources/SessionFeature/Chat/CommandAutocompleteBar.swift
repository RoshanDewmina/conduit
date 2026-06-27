#if os(iOS)
import SwiftUI
import LancerCore
import DesignSystem

// MARK: - CommandAutocompleteBar
//
// The "/" command palette that floats above the composer. Shows Lancer app
// commands (client-side actions) and the live agent commands fetched from the
// daemon, filtered by what the user has typed after the leading "/". The parent
// owns visibility (show when the text starts with "/") and decides what a pick
// does — execute a Lancer action, or insert agent-command text into the prompt.

public struct CommandAutocompleteBar: View {
    /// The full text being typed. Shown only when it starts with "/".
    private let query: String
    private let lancerCommands: [AgentCommand]
    private let agentCommands: [AgentCommand]
    private let onPick: (AgentCommand) -> Void

    @Environment(\.lancerTokens) private var t

    public init(
        query: String,
        lancerCommands: [AgentCommand],
        agentCommands: [AgentCommand],
        onPick: @escaping (AgentCommand) -> Void
    ) {
        self.query = query
        self.lancerCommands = lancerCommands
        self.agentCommands = agentCommands
        self.onPick = onPick
    }

    /// Active only for a leading "/" with no spaces yet (a command token, not prose).
    public var isActive: Bool {
        query.hasPrefix("/") && !query.dropFirst().contains(" ")
    }

    private var needle: String {
        String(query.dropFirst()).lowercased()
    }

    private func matches(_ cmds: [AgentCommand]) -> [AgentCommand] {
        guard !needle.isEmpty else { return cmds }
        return cmds.filter { $0.name.dropFirst().lowercased().hasPrefix(needle) }
    }

    public var body: some View {
        let lancer = matches(lancerCommands)
        let agent = matches(agentCommands)
        if isActive && !(lancer.isEmpty && agent.isEmpty) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        section("LANCER", lancer)
                        section("AGENT", agent)
                    }
                }
                .frame(maxHeight: 240)
            }
            .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(t.border.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ cmds: [AgentCommand]) -> some View {
        if !cmds.isEmpty {
            Text(title)
                .font(.dsMonoPt(9.5, weight: .medium))
                .tracking(1.0)
                .foregroundStyle(t.text4)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)
            ForEach(cmds) { cmd in
                Button {
                    Haptics.selection()
                    onPick(cmd)
                } label: { row(cmd) }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(_ cmd: AgentCommand) -> some View {
        HStack(spacing: 10) {
            Text(cmd.name)
                .font(.dsMonoPt(13, weight: .semibold))
                .foregroundStyle(t.accent)
                .lineLimit(1)
            if !cmd.description.isEmpty {
                Text(cmd.description)
                    .font(.dsSansPt(12.5))
                    .foregroundStyle(t.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            badge(cmd.kind)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func badgeLabel(_ kind: String) -> String {
        switch kind {
        case "skill": return "skill"
        case "builtin": return "built-in"
        case "lancer": return "app"
        default: return ""
        }
    }

    @ViewBuilder
    private func badge(_ kind: String) -> some View {
        let label = badgeLabel(kind)
        if !label.isEmpty {
            Text(label)
                .font(.dsMonoPt(9, weight: .medium))
                .foregroundStyle(t.text4)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(t.surface2, in: Capsule())
        }
    }
}
#endif
