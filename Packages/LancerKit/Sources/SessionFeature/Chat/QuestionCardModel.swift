import Foundation
import LancerCore

/// Pure presentation + action logic for a persisted question artifact.
/// Follows ReceiptCardModel's pattern: no SwiftUI, no side effects, fully
/// testable on macOS (no #if os(iOS) guard).
///
/// Lifecycle:
///   1. A `QuestionPendingParams` arrives from the daemon relay.
///   2. It is stored as a `.question` ChatArtifact via
///      `ChatRunPersistenceSink.handleQuestionPending`.
///   3. `QuestionCardModel.decode(from:)` inflates a `PresentationState` from
///      the artifact's `payloadJSON` (a JSON-encoded `QuestionArtifactPayload`).
///   4. The user selects options / enters free text; mutations go through
///      `toggleOption` and `setFreeText` (pure, value-type).
///   5. `buildAnswer(from:)` produces a `QuestionAnswerParams` the caller sends
///      to the daemon via `DaemonChannel.sendQuestionAnswer` or
///      `E2ERelayBridge.sendQuestionAnswer`.
///   6. `mergeAnswer(into:answer:)` stamps the answer into the stored
///      `payloadJSON`; the updated artifact is upserted via
///      `ChatConversationRepository.upsertArtifact` so the answered state
///      survives app relaunch.
public enum QuestionCardModel {

    // MARK: - Row types

    public struct OptionRow: Equatable, Sendable {
        public let label: String
        public let description: String?

        public init(label: String, description: String? = nil) {
            self.label = label
            self.description = description
        }
    }

    /// Mutable per-item selection state, carrying the original question/options
    /// alongside the user's current picks. Value-type so mutations are explicit.
    public struct ItemState: Equatable, Sendable {
        public let header: String?
        public let question: String
        public let options: [OptionRow]
        public let multiSelect: Bool
        /// Currently selected option labels (ordered to match submit order).
        public var selectedLabels: [String]
        /// Free-text field value (only populated/used when `allowFreeText` is
        /// true on the parent event, or when `options` is empty for a
        /// bestEffort item).
        public var freeText: String

        public init(
            header: String? = nil,
            question: String,
            options: [OptionRow] = [],
            multiSelect: Bool = false,
            selectedLabels: [String] = [],
            freeText: String = ""
        ) {
            self.header = header
            self.question = question
            self.options = options
            self.multiSelect = multiSelect
            self.selectedLabels = selectedLabels
            self.freeText = freeText
        }

        public var hasSelection: Bool { !selectedLabels.isEmpty }

        public func isSelected(_ label: String) -> Bool { selectedLabels.contains(label) }

        /// Wire answer for this item, ready to embed in `QuestionAnswerParams`.
        public var wireAnswer: QuestionItemAnswerWire {
            let trimmed = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
            return QuestionItemAnswerWire(
                selectedLabels: selectedLabels.isEmpty ? nil : selectedLabels,
                freeText: trimmed.isEmpty ? nil : trimmed
            )
        }
    }

    /// Full presentation state for one question card — inflated from a
    /// `QuestionArtifactPayload` and mutated by the card's view state.
    public struct PresentationState: Equatable, Sendable {
        public let questionID: String
        public let agent: String
        public let confidence: String
        public let allowFreeText: Bool
        public var items: [ItemState]
        /// True once the answer has been submitted and persisted.
        public var isAnswered: Bool
        /// The answer that was sent; populated by `markAnswered`.
        public var submittedAnswer: QuestionAnswerParams?

        public init(
            questionID: String,
            agent: String,
            confidence: String,
            allowFreeText: Bool,
            items: [ItemState],
            isAnswered: Bool = false,
            submittedAnswer: QuestionAnswerParams? = nil
        ) {
            self.questionID = questionID
            self.agent = agent
            self.confidence = confidence
            self.allowFreeText = allowFreeText
            self.items = items
            self.isAnswered = isAnswered
            self.submittedAnswer = submittedAnswer
        }
    }

    // MARK: - Decode

    /// Inflate a `PresentationState` from a `.question` artifact. Returns nil
    /// for any other artifact kind or malformed payloadJSON.
    public static func decode(from artifact: ChatArtifact) -> PresentationState? {
        guard artifact.kind == .question else { return nil }
        guard let data = artifact.payloadJSON.data(using: .utf8),
              let payload = try? JSONDecoder().decode(QuestionArtifactPayload.self, from: data) else {
            return nil
        }
        return buildState(from: payload)
    }

    private static func buildState(from payload: QuestionArtifactPayload) -> PresentationState {
        let event = payload.event
        var items = event.questions.map { q -> ItemState in
            let opts = (q.options ?? []).map { OptionRow(label: $0.label, description: $0.description) }
            return ItemState(
                header: q.header,
                question: q.question,
                options: opts,
                multiSelect: q.multiSelect ?? false
            )
        }
        if let answer = payload.answer {
            for (idx, itemAnswer) in answer.items.enumerated() {
                guard idx < items.count else { break }
                items[idx].selectedLabels = itemAnswer.selectedLabels ?? []
                items[idx].freeText = itemAnswer.freeText ?? ""
            }
            return PresentationState(
                questionID: event.id,
                agent: event.agent,
                confidence: event.confidence,
                allowFreeText: event.allowFreeText,
                items: items,
                isAnswered: true,
                submittedAnswer: answer
            )
        }
        return PresentationState(
            questionID: event.id,
            agent: event.agent,
            confidence: event.confidence,
            allowFreeText: event.allowFreeText,
            items: items,
            isAnswered: false
        )
    }

    // MARK: - Mutations

    /// Toggle an option in the item at `itemIndex`. Single-select replaces the
    /// current selection (tapping the already-selected option deselects it);
    /// multi-select adds or removes the label from the ordered list.
    public static func toggleOption(in state: inout PresentationState, itemIndex: Int, label: String) {
        guard itemIndex < state.items.count else { return }
        if state.items[itemIndex].multiSelect {
            if let pos = state.items[itemIndex].selectedLabels.firstIndex(of: label) {
                state.items[itemIndex].selectedLabels.remove(at: pos)
            } else {
                state.items[itemIndex].selectedLabels.append(label)
            }
        } else {
            if state.items[itemIndex].selectedLabels == [label] {
                state.items[itemIndex].selectedLabels = []
            } else {
                state.items[itemIndex].selectedLabels = [label]
            }
        }
    }

    /// Update the free-text field for the item at `itemIndex`.
    public static func setFreeText(in state: inout PresentationState, itemIndex: Int, text: String) {
        guard itemIndex < state.items.count else { return }
        state.items[itemIndex].freeText = text
    }

    // MARK: - Readiness

    /// True when all items have a non-empty answer and the question has not
    /// already been answered. Gating logic:
    /// - An item with options: requires ≥1 selected label, OR (when
    ///   `allowFreeText`) a non-blank free-text entry.
    /// - An options-less item (bestEffort degraded): requires non-blank free text.
    public static func isReadyToAnswer(_ state: PresentationState) -> Bool {
        guard !state.isAnswered else { return false }
        return state.items.allSatisfy { item in
            if item.options.isEmpty {
                return !item.freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let hasLabel = !item.selectedLabels.isEmpty
            let hasFreeText = state.allowFreeText
                && !item.freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasLabel || hasFreeText
        }
    }

    // MARK: - Build answer

    /// Build the `QuestionAnswerParams` wire object from the current state.
    public static func buildAnswer(from state: PresentationState) -> QuestionAnswerParams {
        QuestionAnswerParams(questionId: state.questionID, items: state.items.map(\.wireAnswer))
    }

    // MARK: - Persistence helpers

    /// Merge a submitted answer into a payloadJSON string. The updated string
    /// should be stored by the caller via `ChatConversationRepository.upsertArtifact`
    /// so the answered state survives app relaunch.
    public static func mergeAnswer(into payloadJSON: String, answer: QuestionAnswerParams) -> String? {
        guard let data = payloadJSON.data(using: .utf8),
              var payload = try? JSONDecoder().decode(QuestionArtifactPayload.self, from: data) else {
            return nil
        }
        payload.answer = answer
        guard let updated = try? JSONEncoder().encode(payload) else { return nil }
        return String(data: updated, encoding: .utf8)
    }

    /// True when the artifact's payloadJSON contains a non-nil answer.
    public static func isAnswered(payloadJSON: String) -> Bool {
        guard let data = payloadJSON.data(using: .utf8),
              let payload = try? JSONDecoder().decode(QuestionArtifactPayload.self, from: data) else {
            return false
        }
        return payload.answer != nil
    }

    // MARK: - Confidence caption

    /// Visual caption for a confidence value — same two-tier vocabulary as
    /// `ReceiptCardModel.confidenceCaption` ("Complete" / "Best effort").
    public static func confidenceCaption(_ value: String?) -> String? {
        switch value {
        case "complete":    return "Complete"
        case "bestEffort":  return "Best effort"
        default:            return nil
        }
    }

    // MARK: - Answered summary

    /// A short human-readable summary of a submitted answer for display in the
    /// resolved card state (e.g. "Option A, Option B" or the free text).
    public static func answeredSummary(for item: ItemState) -> String {
        if !item.selectedLabels.isEmpty {
            return item.selectedLabels.joined(separator: ", ")
        }
        let trimmed = item.freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(no answer)" : trimmed
    }

    // MARK: - Fuzzy option matching (voice-answer Siri intent)

    /// Best-effort case-insensitive match of free-form text (e.g. a Siri
    /// voice transcript) against an item's option labels — used when the
    /// caller has no UI to let the user pick a specific option
    /// (`AnswerQuestionResolver`). Exact label equality (case-insensitive)
    /// wins outright; otherwise matching is done on whole words (not raw
    /// substrings) — the longest option label whose word sequence appears
    /// contiguously in the input's words (or vice versa) wins. Word-boundary
    /// matching avoids two failure modes a raw substring check has: a short
    /// label like "A" spuriously matching everything, and a label like "No"
    /// spuriously matching an unrelated word that merely contains those
    /// letters (e.g. "not sure" contains "no" as a raw substring but does
    /// not mean "No"). Returns nil when nothing resembles the input closely
    /// enough, letting the caller fall back to treating it as free text.
    public static func fuzzyMatchOption(_ text: String, in item: ItemState) -> String? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, !item.options.isEmpty else { return nil }
        if let exact = item.options.first(where: { $0.label.lowercased() == normalized }) {
            return exact.label
        }
        let spokenWords = words(in: normalized)
        guard !spokenWords.isEmpty else { return nil }
        let candidates = item.options.filter { option in
            let labelWords = words(in: option.label.lowercased())
            guard !labelWords.isEmpty else { return false }
            return containsSubsequence(labelWords, in: spokenWords)
                || containsSubsequence(spokenWords, in: labelWords)
        }
        return candidates.max(by: { $0.label.count < $1.label.count })?.label
    }

    private static func words(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private static func containsSubsequence(_ needle: [String], in haystack: [String]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle { return true }
        }
        return false
    }
}
