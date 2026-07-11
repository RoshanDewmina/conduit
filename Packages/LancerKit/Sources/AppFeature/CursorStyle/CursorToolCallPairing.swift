import Foundation

/// Id-paired tool-call start/result store with an orphan-result buffer.
///
/// Happier pattern (patterns only — no verbatim code): results that arrive
/// before their matching `tool_use` are buffered and drained when the start
/// lands (`orphanToolResults` / `drainAndApplyOrphanToolResultsToMessage`).
/// States: running | completed | error. Result bodies are capped at 4 KB
/// (Orca `MAX_TOOL_RESULT_CHARS = 4000`).
public struct CursorToolCallPairing: Sendable, Equatable {
    private var cardsByID: [String: CursorToolCallCard] = [:]
    private var order: [String] = []
    private var orphanResults: [String: OrphanResult] = [:]

    private struct OrphanResult: Sendable, Equatable {
        var result: String
        var isError: Bool
    }

    public init() {}

    public var cards: [CursorToolCallCard] {
        order.compactMap { cardsByID[$0] }
    }

    public var bufferedOrphanCount: Int { orphanResults.count }

    public var runningToolName: String? {
        cards.first(where: { $0.state == .running })?.name
    }

    public mutating func applyStart(id: String, name: String, inputJSON: String) {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return }

        if var existing = cardsByID[trimmedID] {
            if !name.isEmpty { existing.name = name }
            existing.inputJSON = inputJSON
            cardsByID[trimmedID] = existing
        } else {
            let card = CursorToolCallCard(
                id: trimmedID,
                name: name.isEmpty ? "Tool" : name,
                state: .running,
                inputJSON: inputJSON
            )
            cardsByID[trimmedID] = card
            order.append(trimmedID)
        }

        drainOrphan(onto: trimmedID)
    }

    public mutating func applyResult(id: String, result: String, isError: Bool) {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return }

        guard var card = cardsByID[trimmedID] else {
            orphanResults[trimmedID] = OrphanResult(result: result, isError: isError)
            return
        }
        card.state = isError ? .error : .completed
        card.resultPreview = CursorToolCallPresentation.capResult(result)
        cardsByID[trimmedID] = card
    }

    private mutating func drainOrphan(onto toolID: String) {
        guard let orphan = orphanResults.removeValue(forKey: toolID),
              var card = cardsByID[toolID]
        else { return }
        card.state = orphan.isError ? .error : .completed
        card.resultPreview = CursorToolCallPresentation.capResult(orphan.result)
        cardsByID[toolID] = card
    }
}
