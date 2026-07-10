import Foundation
import LancerCore

/// Pure resolution logic for the voice-answer Siri intent (`AnswerQuestionIntent`,
/// `Lancer` app target). No `AppIntent` conformance, no I/O — takes a decoded
/// question's `PresentationState` plus one spoken utterance and produces the
/// `QuestionAnswerParams` to send plus a short human-readable summary of what
/// will actually be sent, for the intent's confirmation read-back.
///
/// Kept separate from `AnswerQuestionIntent` itself (which lives in the
/// `Lancer` app target, not a `swift test`-able library target — see that
/// intent's header comment) purely so this piece is unit-testable, mirroring
/// how `RunControlIntents.swift`'s `resolveSoleActiveRun()` free function is
/// pure/small even though its enclosing file lives in the app target.
///
/// Only ever operates on a `.question` artifact's `PresentationState` — this
/// type has no notion of `Approval` at all, by construction.
public enum AnswerQuestionResolver {

    public struct Resolution: Equatable, Sendable {
        /// The wire payload to send via `CommandGateway.execute(.answerQuestion)`.
        public let answer: QuestionAnswerParams
        /// A short summary of what will be sent — one entry per question item,
        /// joined for display — for the intent's "You said '<summary>' — send
        /// this to <agent>?" confirmation read-back.
        public let summary: String
    }

    /// Applies `spokenText` to every item in `state`: for an item with
    /// options, best-effort fuzzy-matches the spoken text against that
    /// item's labels (`QuestionCardModel.fuzzyMatchOption`); otherwise (or
    /// when nothing matches) falls back to free text via
    /// `QuestionCardModel.setFreeText`. The final result is only returned
    /// once `QuestionCardModel.isReadyToAnswer` accepts it — reusing the
    /// model's own readiness gate means an options-only item with
    /// `allowFreeText == false` and no matching option correctly yields
    /// `nil` here (free text alone can't satisfy that item), rather than
    /// this resolver reimplementing that rule separately.
    ///
    /// Returns `nil` for blank input, an already-answered question, or a
    /// question that voice can't resolve given the above rule.
    public static func resolve(
        state: QuestionCardModel.PresentationState,
        spokenText: String
    ) -> Resolution? {
        let trimmed = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !state.items.isEmpty else { return nil }

        var mutable = state
        for idx in mutable.items.indices {
            let item = mutable.items[idx]
            if let matched = QuestionCardModel.fuzzyMatchOption(trimmed, in: item) {
                QuestionCardModel.toggleOption(in: &mutable, itemIndex: idx, label: matched)
            } else {
                QuestionCardModel.setFreeText(in: &mutable, itemIndex: idx, text: trimmed)
            }
        }

        guard QuestionCardModel.isReadyToAnswer(mutable) else { return nil }
        let answer = QuestionCardModel.buildAnswer(from: mutable)
        let summary = mutable.items.map(QuestionCardModel.answeredSummary(for:)).joined(separator: "; ")
        return Resolution(answer: answer, summary: summary)
    }
}
