import AppIntents
import Foundation
import LancerCore
import PersistenceKit
import SessionFeature

// Lives in the `Lancer` app target — see StatusQueryIntents.swift's header
// comment for why (dual-target AppIntent compilation breaks runtime execution
// lookup even though static Shortcuts discovery still works).

/// "Answer the latest question the agent asked" — a voice-answer,
/// confirmation-gated Siri intent for Lane E's question pipeline
/// (`QuestionCardView` / `ChatArtifact.kind == .question`).
///
/// Unlike `DenyLatestApprovalIntent` (executes immediately — deny is
/// safety-reducing, it can only stop an action), this intent reads the
/// resolved answer back to the user and requires an explicit confirm
/// (`requestConfirmation`) before anything is sent to the daemon, because
/// unlike a deny it commits new content into the agent's run. If the user
/// declines the confirmation, `requestConfirmation` throws and `perform`
/// exits without calling `CommandGateway` at all.
///
/// Scope, permanently: this intent ONLY EVER resolves the latest unanswered
/// `.question` `ChatArtifact`, via
/// `ChatConversationRepository.latestUnansweredQuestion()`. It never touches
/// `Approval` / `ApprovalRepository` / `respondApproval` — approving (or
/// otherwise resolving) an agent action stays a visual, in-app or
/// Live-Activity-tap-only decision, never Siri-triggered (see
/// `DenyLatestApprovalIntent`'s doc comment for the full rationale). That
/// rule is not relaxed just because a question's typed options happen to
/// read like an approval decision — answering a question is never the same
/// thing as approving an action, and there is intentionally no
/// Siri-reachable "approve" intent of any kind, for either flow.
///
/// Requires iOS 18 (not the iOS 17 used by the other sibling intents in this
/// file's neighbors) because it uses the non-deprecated
/// `requestConfirmation(conditions:actionName:dialog:)` API, which is
/// iOS 18+ only; the iOS 16+ alternative (`requestConfirmation(result:...)`)
/// is marked deprecated in the SDK. The project's actual deployment target
/// is well above iOS 18, so this has no real-world availability cost — see
/// `LancerAppShortcuts.swift`'s `if #available(iOS 18.0, *)` guard around
/// this intent's single `AppShortcut` registration.
@available(iOS 18.0, *)
public struct AnswerQuestionIntent: AppIntent {
    public static let title: LocalizedStringResource = "Answer Agent Question"
    public static let description = IntentDescription("Answer the most recent question an agent asked, by voice.")

    @Parameter(title: "Answer")
    public var answer: String

    public init() {}

    public init(answer: String) {
        self.answer = answer
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let db = try? AppDatabase.openShared(),
              let artifact = try? await ChatConversationRepository(db).latestUnansweredQuestion(),
              let state = QuestionCardModel.decode(from: artifact)
        else {
            return .result(dialog: "No questions are waiting.")
        }

        guard let resolution = AnswerQuestionResolver.resolve(state: state, spokenText: answer) else {
            return .result(dialog: "Couldn't match that to an answer — open Lancer to answer it directly.")
        }

        try await requestConfirmation(
            dialog: IntentDialog("You said '\(resolution.summary)' — send this to \(state.agent)?")
        )

        switch await CommandGateway.shared.execute(.answerQuestion(id: artifact.id, answer: resolution.answer)) {
        case .ok:
            return .result(dialog: "Sent your answer.")
        case .transportUnavailable:
            return .result(dialog: "Lancer isn't connected to a machine right now.")
        default:
            return .result(dialog: "Couldn't send that answer.")
        }
    }
}
