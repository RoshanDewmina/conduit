import Foundation

/// One agent todo row from a TodoWrite / todo tool payload.
public struct TodoChecklistItem: Equatable, Sendable, Identifiable {
    public enum Status: String, Equatable, Sendable {
        case pending
        case inProgress
        case completed
        case cancelled
    }

    public let id: String
    public let content: String
    public let status: Status

    public init(id: String, content: String, status: Status) {
        self.id = id
        self.content = content
        self.status = status
    }

    public var isComplete: Bool {
        status == .completed || status == .cancelled
    }
}

/// Parsed checklist for the inline To-dos card.
public struct TodoChecklistState: Equatable, Sendable {
    public let items: [TodoChecklistItem]

    public init(items: [TodoChecklistItem]) {
        self.items = items
    }

    public var completedCount: Int {
        items.filter(\.isComplete).count
    }

    public var totalCount: Int { items.count }

    public var title: String {
        "To-dos \(completedCount)/\(totalCount)"
    }
}

/// Pure parser for TodoWrite / todo tool `inputJSON` payloads.
///
/// Shapes informed by happier `normalize/todos.ts` (MIT — happier-dev/happier):
/// `{ "todos": [ { content, status, id? } ] }` plus `items` / bare-array fallbacks.
public enum TodoPayloadParser: Sendable {
    public static func isTodoTool(name: String) -> Bool {
        switch TurnTranscriptAssembler.normalizeToolName(name) {
        case "todowrite", "todo_write", "todo", "todos",
             "write_todos", "update_todos", "todolist", "todo_list":
            return true
        default:
            // Cursor / Claude often report the literal tool name "TodoWrite".
            let folded = name.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "_", with: "")
                .lowercased()
            return folded == "todowrite" || folded == "updatetodos"
        }
    }

    /// Latest parseable todo checklist among tool chips (last write wins).
    public static func latestChecklist(from items: [TurnTranscriptItem]) -> TodoChecklistState? {
        var latest: TodoChecklistState?
        for item in items {
            guard case .toolChip(let chip) = item, isTodoTool(name: chip.name) else { continue }
            if let state = parse(chip.inputJSON) {
                latest = state
            }
        }
        return latest
    }

    public static func parse(_ inputJSON: String?) -> TodoChecklistState? {
        guard let inputJSON else { return nil }
        let trimmed = inputJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }

        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }

        let rawItems = extractRawTodoArray(from: root)
        guard let rawItems else { return nil }

        var items: [TodoChecklistItem] = []
        items.reserveCapacity(rawItems.count)
        for (index, value) in rawItems.enumerated() {
            if let item = coerceItem(value, fallbackIndex: index) {
                items.append(item)
            }
        }
        guard !items.isEmpty else { return nil }
        return TodoChecklistState(items: items)
    }

    // MARK: - Private

    private static func extractRawTodoArray(from root: Any) -> [Any]? {
        if let array = root as? [Any] {
            return array
        }
        guard let obj = root as? [String: Any] else { return nil }
        if let todos = obj["todos"] as? [Any] { return todos }
        if let items = obj["items"] as? [Any] { return items }
        if let nested = obj["input"] as? [String: Any] {
            if let todos = nested["todos"] as? [Any] { return todos }
            if let items = nested["items"] as? [Any] { return items }
        }
        if let acp = obj["_acp"] as? [String: Any],
           let raw = acp["rawInput"] as? [Any] {
            return raw
        }
        return nil
    }

    private static func coerceItem(_ value: Any, fallbackIndex: Int) -> TodoChecklistItem? {
        if let string = value as? String {
            let content = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            return TodoChecklistItem(
                id: "todo-\(fallbackIndex)",
                content: content,
                status: .pending
            )
        }
        guard let obj = value as? [String: Any] else { return nil }
        let content = firstString(obj, keys: ["content", "title", "text"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let content, !content.isEmpty else { return nil }
        let id = firstString(obj, keys: ["id"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? "todo-\(fallbackIndex)"
        let status = normalizeStatus(firstString(obj, keys: ["status", "state"]))
        return TodoChecklistItem(id: id, content: content, status: status)
    }

    private static func normalizeStatus(_ raw: String?) -> TodoChecklistItem.Status {
        guard let raw else { return .pending }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pending", "todo":
            return .pending
        case "in_progress", "in-progress", "doing", "inprogress":
            return .inProgress
        case "completed", "done", "complete":
            return .completed
        case "cancelled", "canceled":
            return .cancelled
        default:
            return .pending
        }
    }

    private static func firstString(_ obj: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let s = obj[key] as? String { return s }
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
