import Foundation

/// Pure consecutive-chip aggregation + Claude Code app collapsed titles (CC-2)
/// and terminal-turn chip status forcing (WT-B). OS-agnostic for unit tests.
public enum ToolChipGrouping: Sendable {
    public enum ToolKind: Equatable, Sendable {
        case command
        case edit
        case read
        case other
    }

    /// Collapse consecutive tool chips; prose/thinking break runs (do not merge across).
    public static func groupedForDisplay(_ items: [TurnTranscriptItem]) -> [TurnTranscriptRenderItem] {
        var out: [TurnTranscriptRenderItem] = []
        var chipRun: [ToolChipItem] = []

        func flushChips() {
            guard !chipRun.isEmpty else { return }
            out.append(.toolChips(chipRun))
            chipRun = []
        }

        for item in items {
            switch item {
            case .prose(let prose):
                flushChips()
                out.append(.prose(prose))
            case .thinking(let thinking):
                flushChips()
                out.append(.thinking(thinking))
            case .toolChip(let chip):
                chipRun.append(chip)
            }
        }
        flushChips()
        return out
    }

    /// Apply WT-B: when the turn is terminal, no chip may remain `.running`.
    public static func withTerminalTurnStatus(
        _ chips: [ToolChipItem],
        turnIsTerminal: Bool
    ) -> [ToolChipItem] {
        guard turnIsTerminal else { return chips }
        return chips.map { chip in
            guard chip.status == .running else { return chip }
            return ToolChipItem(
                id: chip.id,
                toolUseId: chip.toolUseId,
                name: chip.name,
                inputJSON: chip.inputJSON,
                resultText: chip.resultText,
                added: chip.added,
                removed: chip.removed,
                isError: chip.isError,
                status: chip.isError ? .failed : .done
            )
        }
    }

    public static func displayGroups(
        from items: [TurnTranscriptItem],
        turnIsTerminal: Bool
    ) -> [TurnTranscriptRenderItem] {
        let adjusted: [TurnTranscriptItem] = items.map { item in
            guard case .toolChip(let chip) = item else { return item }
            let forced = withTerminalTurnStatus([chip], turnIsTerminal: turnIsTerminal)
            return .toolChip(forced[0])
        }
        return groupedForDisplay(adjusted)
    }

    public static func kind(forToolName name: String) -> ToolKind {
        switch TurnTranscriptAssembler.normalizeToolName(name) {
        case "bash", "shell", "command":
            return .command
        case "edit", "write", "strreplace", "applypatch", "apply_patch":
            return .edit
        case "read", "readfile", "read_file":
            return .read
        default:
            return .other
        }
    }

    /// Collapsed group label matching Claude Code app wording.
    public static func collapsedTitle(for chips: [ToolChipItem]) -> String {
        guard !chips.isEmpty else { return "Tools" }
        if chips.count == 1 {
            return TurnTranscriptAssembler.chipTitle(
                name: chips[0].name,
                inputJSON: chips[0].inputJSON
            )
        }

        let kinds = chips.map { kind(forToolName: $0.name) }
        if kinds.allSatisfy({ $0 == .command }) {
            return "Ran \(chips.count) commands"
        }
        if kinds.allSatisfy({ $0 == .read }) {
            return "Read \(chips.count) files"
        }
        if kinds.allSatisfy({ $0 == .edit }) {
            return "Edited \(chips.count) files"
        }

        var parts: [String] = ["Used \(chips.count) tools"]
        let commandCount = kinds.filter { $0 == .command }.count
        let editCount = kinds.filter { $0 == .edit }.count
        if commandCount == 1 {
            parts.append("ran a command")
        } else if commandCount > 1 {
            parts.append("ran \(commandCount) commands")
        }
        if editCount == 1 {
            parts.append("edited a file")
        } else if editCount > 1 {
            parts.append("edited \(editCount) files")
        }
        return parts.joined(separator: ", ")
    }

    /// Real wall duration: never `0` when `completedAt` is after `startedAt`.
    public static func durationSeconds(startedAt: Date, completedAt: Date) -> Int {
        let interval = completedAt.timeIntervalSince(startedAt)
        if interval <= 0 { return 0 }
        return max(1, Int(ceil(interval)))
    }
}
