import Foundation

/// Parsed Edit / Write / MultiEdit tool input for the red/green diff sheet.
/// Built from the raw `inputJSON` already on the phone (no extra RPC).
public struct EditToolDiffPresentation: Equatable, Sendable, Identifiable {
    public struct Segment: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String?
        public let deletions: [DiffDisplayRow]
        public let additions: [DiffDisplayRow]

        public init(id: String, title: String? = nil, deletions: [DiffDisplayRow], additions: [DiffDisplayRow]) {
            self.id = id
            self.title = title
            self.deletions = deletions
            self.additions = additions
        }

        public var addedCount: Int { additions.count }
        public var removedCount: Int { deletions.count }
    }

    public let toolName: String
    public let filePath: String?
    public let segments: [Segment]

    public var id: String {
        "\(TurnTranscriptAssembler.normalizeToolName(toolName))|\(filePath ?? "")|\(segments.map(\.id).joined(separator: ","))"
    }

    public init(toolName: String, filePath: String?, segments: [Segment]) {
        self.toolName = toolName
        self.filePath = filePath
        self.segments = segments
    }

    public var fileName: String {
        guard let filePath, !filePath.isEmpty else { return "File" }
        return ChatFileNameDisplay.displayName(for: filePath)
    }

    public var navigationTitle: String {
        switch TurnTranscriptAssembler.normalizeToolName(toolName) {
        case "write": return "Write"
        case "multiedit": return "MultiEdit"
        default: return "Edit"
        }
    }

    public var totalAdded: Int { segments.reduce(0) { $0 + $1.addedCount } }
    public var totalRemoved: Int { segments.reduce(0) { $0 + $1.removedCount } }

    public var countsLabel: String { "+\(totalAdded) −\(totalRemoved)" }

    public var isEmpty: Bool { segments.isEmpty || segments.allSatisfy { $0.deletions.isEmpty && $0.additions.isEmpty } }
}

public enum EditToolDiffParser {
    /// Tools that own old/new (or write content) payloads worth showing as a sheet.
    public static func supportsDiffSheet(toolName: String) -> Bool {
        switch TurnTranscriptAssembler.normalizeToolName(toolName) {
        case "edit", "write", "multiedit":
            return true
        default:
            return false
        }
    }

    public static func parse(toolName: String, inputJSON: String?) -> EditToolDiffPresentation? {
        guard supportsDiffSheet(toolName: toolName) else { return nil }
        guard let object = decodeObject(inputJSON) else { return nil }

        let path = stringValue(object["file_path"]) ?? stringValue(object["path"])
        let normalized = TurnTranscriptAssembler.normalizeToolName(toolName)

        switch normalized {
        case "edit":
            let old = stringValue(object["old_string"]) ?? ""
            let new = stringValue(object["new_string"]) ?? ""
            guard !old.isEmpty || !new.isEmpty else { return nil }
            let segment = Segment(
                id: "edit-0",
                deletions: rows(from: old, kind: .del, idPrefix: "del"),
                additions: rows(from: new, kind: .add, idPrefix: "add")
            )
            return EditToolDiffPresentation(toolName: toolName, filePath: path, segments: [segment])

        case "write":
            let content = stringValue(object["content"]) ?? ""
            guard !content.isEmpty else { return nil }
            let segment = Segment(
                id: "write-0",
                deletions: [],
                additions: rows(from: content, kind: .add, idPrefix: "add")
            )
            return EditToolDiffPresentation(toolName: toolName, filePath: path, segments: [segment])

        case "multiedit":
            guard let edits = object["edits"] as? [[String: Any]], !edits.isEmpty else { return nil }
            var segments: [EditToolDiffPresentation.Segment] = []
            for (index, edit) in edits.enumerated() {
                let old = stringValue(edit["old_string"]) ?? ""
                let new = stringValue(edit["new_string"]) ?? ""
                if old.isEmpty && new.isEmpty { continue }
                segments.append(
                    Segment(
                        id: "multiedit-\(index)",
                        title: "Edit \(index + 1)",
                        deletions: rows(from: old, kind: .del, idPrefix: "d\(index)"),
                        additions: rows(from: new, kind: .add, idPrefix: "a\(index)")
                    )
                )
            }
            guard !segments.isEmpty else { return nil }
            return EditToolDiffPresentation(toolName: toolName, filePath: path, segments: segments)

        default:
            return nil
        }
    }

    // MARK: - Helpers

    private typealias Segment = EditToolDiffPresentation.Segment

    private static func decodeObject(_ json: String?) -> [String: Any]? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let obj = root as? [String: Any] {
            // Live artifact payloads sometimes wrap the tool input.
            if let nested = obj["input"] as? [String: Any] {
                return nested
            }
            if let nestedString = obj["input"] as? String,
               let nestedData = nestedString.data(using: .utf8),
               let nestedObj = try? JSONSerialization.jsonObject(with: nestedData) as? [String: Any]
            {
                return nestedObj
            }
            return obj
        }
        return nil
    }

    private static func stringValue(_ any: Any?) -> String? {
        guard let any else { return nil }
        if let s = any as? String { return s }
        return nil
    }

    private static func rows(from text: String, kind: RepoDiffLine.Kind, idPrefix: String) -> [DiffDisplayRow] {
        guard !text.isEmpty else { return [] }
        // Drop a single trailing empty split from a terminating newline (editor line count).
        let parts = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let lines: [String]
        if parts.count > 1, parts.last == "" {
            lines = Array(parts.dropLast())
        } else {
            lines = parts
        }
        return lines.enumerated().map { index, line in
            let oldNo = kind == .del ? index + 1 : nil
            let newNo = kind == .add ? index + 1 : nil
            return DiffDisplayRow(
                id: "\(idPrefix)-\(index)",
                kind: kind,
                oldNo: oldNo,
                newNo: newNo,
                text: line,
                displayLineNumber: kind == .del ? oldNo : newNo
            )
        }
    }
}
