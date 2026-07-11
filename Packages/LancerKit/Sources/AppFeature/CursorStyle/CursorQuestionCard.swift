import Foundation
import LancerCore
import SessionFeature

/// Pure decode + presentation helpers for the CursorStyle in-thread question card.
/// No `#if os(iOS)` — host-runnable via `swift test` (mirrors `CursorToolCallPresentation`).
///
/// Wire conversion is the 30a28e26 fix: relay `E2ERelayMessage.QuestionData` is keyed
/// `questionID` (not SSH `QuestionPendingParams.id`). Copy stays "asked of the agent"
/// — never a guarantee the agent will proceed.
public enum CursorQuestionCardModel: Sendable {
    /// Status detail when `CursorThreadAttention` derives `.blockingQuestion`.
    public static let awaitingInputDetail = "A question was asked of the agent"

    /// Header label for the live pending card.
    public static let cardTitle = "Question"

    /// Convert the relay wire payload into the SSH-path `QuestionPendingParams`
    /// shape used by `QuestionArtifactPayload` / `QuestionCardModel`.
    public static func pendingParams(from wire: E2ERelayMessage.QuestionData) -> QuestionPendingParams {
        QuestionPendingParams(
            id: wire.questionID,
            agent: wire.agent,
            runId: wire.runId,
            cwd: wire.cwd,
            questions: wire.questions,
            allowFreeText: wire.allowFreeText,
            confidence: wire.confidence
        )
    }

    /// Inflate card presentation directly from a relay `QuestionData` payload.
    /// Returns nil only if the synthetic artifact decode fails (should not happen
    /// for well-formed wire data).
    public static func presentation(from wire: E2ERelayMessage.QuestionData) -> QuestionCardModel.PresentationState? {
        let params = pendingParams(from: wire)
        guard let payloadData = try? JSONEncoder().encode(QuestionArtifactPayload(event: params)),
              let payloadJSON = String(data: payloadData, encoding: .utf8)
        else { return nil }
        let artifact = ChatArtifact(
            id: "question:\(params.id)",
            conversationID: "",
            turnID: "",
            runID: params.runId ?? "",
            kind: .question,
            title: cardTitle,
            payloadJSON: payloadJSON,
            status: .running
        )
        return QuestionCardModel.decode(from: artifact)
    }

    /// Whether the live inset card should render for this state.
    public static func shouldShowCard(_ state: QuestionCardModel.PresentationState?) -> Bool {
        guard let state, !state.isAnswered else { return false }
        return true
    }

    /// True when a transcript `.question` artifact should be suppressed because
    /// the live pending card already covers the same unanswered question.
    public static func shouldSuppressTranscriptArtifact(
        artifact: ChatArtifact,
        pending: QuestionCardModel.PresentationState?
    ) -> Bool {
        guard shouldShowCard(pending),
              artifact.kind == .question,
              let decoded = QuestionCardModel.decode(from: artifact),
              !decoded.isAnswered,
              decoded.questionID == pending?.questionID
        else { return false }
        return true
    }
}

#if os(iOS)
import SwiftUI
import DesignSystem

/// Live pending question card for `CursorWorkThreadView` — options / free-text /
/// submit, driven by `QuestionCardModel.PresentationState` (M1 shape) rather than
/// a persisted artifact. Answering is NOT an approval.
public struct CursorQuestionCard: View {
    let state: QuestionCardModel.PresentationState
    let onToggleOption: (Int, String) -> Void
    let onSetFreeText: (Int, String) -> Void
    let onSubmit: () -> Void

    @Environment(\.cursorScheme) private var cursorScheme

    public init(
        state: QuestionCardModel.PresentationState,
        onToggleOption: @escaping (Int, String) -> Void,
        onSetFreeText: @escaping (Int, String) -> Void,
        onSubmit: @escaping () -> Void
    ) {
        self.state = state
        self.onToggleOption = onToggleOption
        self.onSetFreeText = onSetFreeText
        self.onSubmit = onSubmit
    }

    private var colors: CursorColors { CursorColors.resolve(cursorScheme) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ForEach(Array(state.items.enumerated()), id: \.offset) { index, item in
                itemSection(item, itemIndex: index)
            }
            Button(action: onSubmit) {
                Text("Submit answer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(colors.orangeAccent)
            .disabled(!QuestionCardModel.isReadyToAnswer(state))
            .accessibilityIdentifier("cursor-question-card-submit")
        }
        .padding(14)
        .background(colors.cardBackground, in: RoundedRectangle(cornerRadius: CursorMetrics.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CursorMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(colors.hairline, lineWidth: 0.75)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cursor-question-card")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(colors.orangeAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(CursorQuestionCardModel.cardTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.primaryText)
                Text(CursorQuestionCardModel.awaitingInputDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(colors.secondaryText)
            }
            Spacer(minLength: 0)
            if let caption = QuestionCardModel.confidenceCaption(state.confidence) {
                Text(caption)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.secondaryText)
            }
        }
    }

    private func itemSection(_ item: QuestionCardModel.ItemState, itemIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header = item.header {
                Text(header)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.secondaryText)
            }
            Text(item.question)
                .font(.system(size: 15))
                .foregroundStyle(colors.primaryText)

            ForEach(item.options, id: \.label) { option in
                Button {
                    onToggleOption(itemIndex, option.label)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.isSelected(option.label) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isSelected(option.label) ? colors.orangeAccent : colors.secondaryText)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label)
                                .font(.system(size: 14))
                                .foregroundStyle(colors.primaryText)
                            if let description = option.description {
                                Text(description)
                                    .font(.system(size: 12))
                                    .foregroundStyle(colors.secondaryText)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }

            if item.options.isEmpty || state.allowFreeText {
                TextField(
                    item.options.isEmpty ? "Type your answer…" : "Or type a free-text answer…",
                    text: Binding(
                        get: { item.freeText },
                        set: { onSetFreeText(itemIndex, $0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
            }
        }
    }
}
#endif
