import Foundation
import LancerCore

/// Pure fold / summary / auto-expand / result-cap helpers for tool-call cards.
/// No `#if os(iOS)` — testable via `swift test` on macOS.
///
/// Orca (MIT) ports with attribution:
/// - summarize/brief/run summary ← `native-chat-tool-summary.ts`
/// - 4 KB result cap ← `NativeChatToolRun.tsx` `MAX_TOOL_RESULT_CHARS = 4000`
/// Happier auto-expand band (patterns only):
/// - `resolveToolCallsGroupAutoExpandPolicy.ts` — `max(preview*2, 6)`
public enum CursorToolCallPresentation {
    /// ported from stablyai/orca NativeChatToolRun.tsx
    public static let maxResultUTF8Count = 4000
    /// ported from stablyai/orca native-chat-tool-summary.ts
    public static let maxPreviewLength = 80
    /// Happier floor for the auto-expand upper band.
    public static let minAutoExpandLimit = 6
    public static let defaultCollapsedPreviewCount = 3

    // MARK: - Result cap

    /// Cap a tool result body at 4 KB (UTF-8), appending an ellipsis when truncated.
    /// ported from stablyai/orca NativeChatToolRun.tsx
    public static func capResult(_ raw: String) -> String {
        let utf8 = Array(raw.utf8)
        guard utf8.count > maxResultUTF8Count else { return raw }
        var end = maxResultUTF8Count
        // Walk back so we don't split a multi-byte scalar.
        while end > 0 && (utf8[end] & 0b1100_0000) == 0b1000_0000 {
            end -= 1
        }
        let truncated = String(bytes: utf8[..<end], encoding: .utf8) ?? String(raw.prefix(maxResultUTF8Count))
        return truncated + "…"
    }

    // MARK: - Summaries (ported from stablyai/orca native-chat-tool-summary.ts)

    /// One-line, length-capped preview of a tool-call input payload.
    public static func summarizeToolInput(_ input: String) -> String {
        let raw = toRawPreview(input)
        let collapsed = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > maxPreviewLength else { return collapsed }
        let idx = collapsed.index(collapsed.startIndex, offsetBy: maxPreviewLength - 1)
        return String(collapsed[..<idx]) + "…"
    }

    /// Short hint: basename of a path field when present, else clipped input.
    public static func briefToolArg(_ inputJSON: String) -> String {
        if let obj = jsonObject(inputJSON) {
            if let path = stringValue(obj, keys: ["file_path", "path", "notebook_path"]),
               !path.isEmpty {
                return (path as NSString).lastPathComponent
            }
            if let cmd = stringValue(obj, keys: ["command", "cmd", "query", "pattern"]) {
                let clipped = summarizeToolInput(cmd)
                return String(clipped.prefix(28))
            }
        }
        return String(summarizeToolInput(inputJSON).prefix(28))
    }

    /// One-line summary of a run: "Bash git status · Edit app.tsx".
    public static func summarizeToolRun(_ cards: [CursorToolCallCard]) -> String {
        cards
            .map(\.oneLineLabel)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "  ·  ")
    }

    // MARK: - Auto-expand (Happier pattern)

    public static func autoExpandLimit(collapsedPreviewCount: Int) -> Int {
        let preview = max(0, collapsedPreviewCount)
        return max(minAutoExpandLimit, preview * 2)
    }

    /// Auto-expand only small groups just above the collapsed preview count —
    /// medium/large groups stay collapsed so they don't dominate the transcript.
    public static func shouldAutoExpandGroup(
        toolCount: Int,
        collapsedPreviewCount: Int = defaultCollapsedPreviewCount
    ) -> Bool {
        let count = max(0, toolCount)
        let preview = max(0, collapsedPreviewCount)
        if count <= preview { return false }
        return count <= autoExpandLimit(collapsedPreviewCount: preview)
    }

    public static func makeGroup(
        cards: [CursorToolCallCard],
        collapsedPreviewCount: Int = defaultCollapsedPreviewCount
    ) -> CursorToolCallGroup {
        let summary = summarizeToolRun(cards)
        let fallback: String
        if cards.count == 1 {
            fallback = "1 tool call"
        } else {
            fallback = "\(cards.count) tool calls"
        }
        return CursorToolCallGroup(
            cards: cards,
            summaryLine: summary.isEmpty ? fallback : summary,
            shouldAutoExpand: shouldAutoExpandGroup(
                toolCount: cards.count,
                collapsedPreviewCount: collapsedPreviewCount
            )
        )
    }

    // MARK: - Artifacts → cards

    public static func cardsFromArtifacts(_ artifacts: [ChatArtifact]) -> [CursorToolCallCard] {
        var pairing = CursorToolCallPairing()
        let tools = artifacts
            .filter { $0.kind == .tool }
            .sorted { $0.createdAt < $1.createdAt }
        for artifact in tools {
            pairing.applyStart(
                id: artifact.id,
                name: artifact.title,
                inputJSON: artifact.payloadJSON
            )
            switch artifact.status {
            case .running:
                break
            case .done:
                let body = artifact.summary ?? artifact.payloadJSON
                pairing.applyResult(id: artifact.id, result: body, isError: false)
            case .failed:
                let body = artifact.summary ?? artifact.payloadJSON
                pairing.applyResult(id: artifact.id, result: body, isError: true)
            }
        }
        return pairing.cards
    }

    // MARK: - Private

    private static func toRawPreview(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let obj = jsonObject(trimmed) {
            if let command = stringValue(obj, keys: ["command", "cmd"]) {
                return command
            }
            if let path = stringValue(obj, keys: ["file_path", "path", "notebook_path"]) {
                return path
            }
            if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
               let compact = String(data: data, encoding: .utf8) {
                return compact
            }
        }
        return trimmed
    }

    private static func jsonObject(_ raw: String) -> [String: Any]? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    private static func stringValue(_ obj: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = obj[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
