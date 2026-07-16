import Foundation
import LancerCore

#if os(iOS)
import SwiftUI
#endif

/// Pure mapping from live transcript tool chips → background-task rows.
/// Count source: `ToolChipItem` with `.running` / `.done` from
/// `TurnTranscriptAssembler` (events + live tool artifacts) — no polling.
public enum BackgroundTasksPresentation: Sendable {
    public enum Status: String, Sendable, Hashable {
        case running
        case finished
    }

    public struct TaskRow: Identifiable, Sendable, Hashable {
        public let id: String
        public let title: String
        public let typeLabel: String
        public let startedAt: Date?
        public let status: Status

        public init(
            id: String,
            title: String,
            typeLabel: String,
            startedAt: Date? = nil,
            status: Status
        ) {
            self.id = id
            self.title = title
            self.typeLabel = typeLabel
            self.startedAt = startedAt
            self.status = status
        }
    }

    /// Build rows from assembled tool chips. `startedAtByToolUseId` comes from
    /// matching `tool_call` / artifact `createdAt` when available.
    public static func rows(
        from chips: [ToolChipItem],
        startedAtByToolUseId: [String: Date] = [:]
    ) -> [TaskRow] {
        chips.compactMap { chip in
            let status: Status
            switch chip.status {
            case .running:
                status = .running
            case .done:
                status = .finished
            case .failed:
                return nil
            }
            return TaskRow(
                id: chip.id,
                title: taskTitle(name: chip.name, inputJSON: chip.inputJSON),
                typeLabel: typeLabel(name: chip.name),
                startedAt: startedAtByToolUseId[chip.toolUseId] ?? startedAtByToolUseId[chip.id],
                status: status
            )
        }
    }

    public static func runningCount(in rows: [TaskRow]) -> Int {
        rows.filter { $0.status == .running }.count
    }

    public static func running(in rows: [TaskRow]) -> [TaskRow] {
        rows.filter { $0.status == .running }
    }

    public static func finished(in rows: [TaskRow]) -> [TaskRow] {
        rows.filter { $0.status == .finished }
    }

    public static func pillLabel(runningCount: Int) -> String {
        runningCount == 1 ? "1 running task" : "\(runningCount) running tasks"
    }

    public static func taskTitle(name: String, inputJSON: String?) -> String {
        let normalized = TurnTranscriptAssembler.normalizeToolName(name)
        if ["bash", "shell", "command"].contains(normalized),
           let command = commandSummary(from: inputJSON) {
            return command
        }
        return TurnTranscriptAssembler.chipTitle(name: name, inputJSON: inputJSON)
    }

    public static func typeLabel(name: String) -> String {
        switch TurnTranscriptAssembler.normalizeToolName(name) {
        case "bash", "shell", "command":
            return "Shell"
        case "read":
            return "Read"
        case "edit":
            return "Edit"
        case "write":
            return "Write"
        default:
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "Tool" }
            return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
        }
    }

    /// Elapsed caption for a running row (`14s`, `2m 14s`, …).
    public static func elapsedLabel(startedAt: Date?, now: Date) -> String? {
        guard let startedAt else { return nil }
        let seconds = max(0, Int(now.timeIntervalSince(startedAt)))
        return LiveStatusPresentation.formatElapsed(seconds)
    }

    public static func toolUseId(from event: ChatEvent) -> String? {
        guard let json = event.payloadJSON, let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return event.text.flatMap { $0.isEmpty ? nil : $0 }
        }
        if let id = obj["toolUseId"] as? String ?? obj["tool_use_id"] as? String, !id.isEmpty {
            return id
        }
        return event.text.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Collect chip rows + start times from assembled transcript items and events.
    public static func rows(
        items: [TurnTranscriptItem],
        events: [ChatEvent],
        artifacts: [ChatArtifact] = []
    ) -> [TaskRow] {
        var chips: [ToolChipItem] = []
        for item in items {
            if case .toolChip(let chip) = item {
                chips.append(chip)
            }
        }
        let existingIDs = Set(chips.map(\.toolUseId))
        for artifact in artifacts {
            let chip = ToolChipItem(artifact: artifact)
            if !existingIDs.contains(chip.toolUseId) {
                chips.append(chip)
            }
        }
        var startedAt: [String: Date] = [:]
        for event in events where event.kind == "tool_call" {
            if let id = toolUseId(from: event) {
                startedAt[id] = event.createdAt
            }
        }
        for artifact in artifacts {
            let chip = ToolChipItem(artifact: artifact)
            startedAt[chip.toolUseId] = artifact.createdAt
        }
        var byToolUseId: [String: ToolChipItem] = [:]
        for chip in chips {
            byToolUseId[chip.toolUseId] = chip
        }
        return rows(from: Array(byToolUseId.values), startedAtByToolUseId: startedAt)
    }

    // MARK: - Private

    private static func commandSummary(from inputJSON: String?) -> String? {
        guard let inputJSON, let data = inputJSON.data(using: .utf8) else { return nil }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let raw = (obj["command"] as? String)
                ?? (obj["cmd"] as? String)
                ?? (obj["script"] as? String)
            guard let raw else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let firstLine = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                .first
                .map(String.init) ?? trimmed
            if firstLine.count <= 80 { return firstLine }
            return String(firstLine.prefix(79)) + "…"
        }
        return nil
    }
}

#if os(iOS)
/// Capsule above the follow-up composer: "N running tasks". Hidden when N == 0.
struct BackgroundTasksPill: View {
    let runningCount: Int
    var onTap: () -> Void

    var body: some View {
        if runningCount > 0 {
            Button(action: onTap) {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(BackgroundTasksPresentation.pillLabel(runningCount: runningCount))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
                .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("background-tasks-pill")
            .accessibilityLabel(Text(BackgroundTasksPresentation.pillLabel(runningCount: runningCount)))
        }
    }
}
#endif
