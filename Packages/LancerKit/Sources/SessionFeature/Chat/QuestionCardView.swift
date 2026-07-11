#if os(iOS)
import SwiftUI
import LancerCore
import DesignSystem

/// Chat-thread card that renders a `QuestionEvent` from the daemon and lets the
/// user select options (Ladder) and/or enter free text, then submit an answer.
/// A3-R4 Cursor-language pass: draws exclusively from `CursorColors`/`CursorType`
/// (this card is only ever hosted by the Cursor-style `CursorWorkThreadView`).
///
/// Visual contract:
/// - Left gutter accent: `orangeAccent` while pending, `successGreen` once answered.
/// - Header: "Question › agent" label, plus a "Best effort" badge when
///   `confidence == "bestEffort"`.
/// - Each `QuestionItem` shows as a labeled option row (tappable pill-style
///   buttons); multi-select items allow multiple choices.
/// - A free-text field appears when `allowFreeText` is true (always for
///   bestEffort / options-less items).
/// - "Submit answer" pill CTA, enabled only when `isReadyToAnswer`.
/// - Answered state: gutter turns green, options/free-text become read-only,
///   the submitted selection is shown.
public struct QuestionCardView: View {
    let artifact: ChatArtifact
    let onAnswer: (QuestionAnswerParams) -> Void

    @State private var state: QuestionCardModel.PresentationState?
    @Environment(\.cursorScheme) private var cursorScheme

    public init(
        artifact: ChatArtifact,
        initialState: QuestionCardModel.PresentationState? = nil,
        onAnswer: @escaping (QuestionAnswerParams) -> Void
    ) {
        self.artifact = artifact
        self.onAnswer = onAnswer
        self._state = State(initialValue: initialState ?? QuestionCardModel.decode(from: artifact))
    }

    private var colors: CursorColors { CursorColors.resolve(cursorScheme) }

    public var body: some View {
        if let s = state {
            content(s)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func content(_ s: QuestionCardModel.PresentationState) -> some View {
        HStack(alignment: .top, spacing: 0) {
            gutterBar(answered: s.isAnswered)

            VStack(alignment: .leading, spacing: 0) {
                header(s)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)

                ForEach(Array(s.items.enumerated()), id: \.offset) { idx, item in
                    sectionDivider
                    itemSection(s: s, item: item, idx: idx)
                }

                sectionDivider
                if s.isAnswered {
                    answeredFooter(s)
                } else {
                    submitSection(s)
                }
            }
        }
        .background(colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CursorMetrics.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CursorMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(s.isAnswered ? colors.successGreen.opacity(0.35) : colors.hairline, lineWidth: 0.75)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("question-card")
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    // MARK: - Gutter

    private func gutterBar(answered: Bool) -> some View {
        Rectangle()
            .fill(answered ? colors.successGreen.opacity(0.55) : colors.orangeAccent)
            .frame(width: 3)
    }

    // MARK: - Header

    private func header(_ s: QuestionCardModel.PresentationState) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Question")
                        .foregroundColor(colors.secondaryText)
                        .fontWeight(.semibold)
                    Text("›")
                        .foregroundColor(colors.mutedText)
                    Text(s.agent)
                        .foregroundColor(colors.mutedText)
                }
                .font(CursorType.sectionHeader)
                .tracking(0.5)
                .textCase(.uppercase)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if s.confidence == "bestEffort" {
                bestEffortBadge
            }

            if s.isAnswered {
                answeredBadge
            }
        }
    }

    private var bestEffortBadge: some View {
        Text("Best effort")
            .font(CursorType.statusPill)
            .foregroundColor(colors.secondaryText)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(colors.cardBackground)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(colors.hairline, lineWidth: 0.5))
            .accessibilityIdentifier("question-best-effort-badge")
    }

    private var answeredBadge: some View {
        CursorStatusBadge(kind: .success, label: "Answered")
            .accessibilityIdentifier("question-answered-badge")
    }

    // MARK: - Item section

    private func itemSection(s: QuestionCardModel.PresentationState, item: QuestionCardModel.ItemState, idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let header = item.header, !header.isEmpty {
                Text(header.uppercased())
                    .font(CursorType.sectionHeader)
                    .tracking(0.5)
                    .foregroundColor(colors.mutedText)
            }

            Text(item.question)
                .font(CursorType.bodyText)
                .foregroundColor(colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            if !item.options.isEmpty {
                optionsGrid(s: s, item: item, idx: idx)
            }

            if s.allowFreeText || item.options.isEmpty {
                freeTextField(s: s, item: item, idx: idx)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func optionsGrid(s: QuestionCardModel.PresentationState, item: QuestionCardModel.ItemState, idx: Int) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(item.options, id: \.label) { opt in
                optionButton(s: s, item: item, itemIdx: idx, opt: opt)
            }
        }
    }

    private func optionButton(
        s: QuestionCardModel.PresentationState,
        item: QuestionCardModel.ItemState,
        itemIdx: Int,
        opt: QuestionCardModel.OptionRow
    ) -> some View {
        let selected = item.isSelected(opt.label)
        return Button {
            guard !s.isAnswered else { return }
            guard var updated = state else { return }
            QuestionCardModel.toggleOption(in: &updated, itemIndex: itemIdx, label: opt.label)
            state = updated
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(opt.label)
                    .font(CursorType.pillLabel)
                    .fontWeight(selected ? .semibold : .medium)
                    .foregroundColor(selected ? colors.pillPrimaryText : colors.primaryText)
                if let desc = opt.description, !desc.isEmpty {
                    Text(desc)
                        .font(CursorType.rowSecondary)
                        .foregroundColor(selected ? colors.pillPrimaryText.opacity(0.8) : colors.secondaryText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selected ? colors.pillPrimaryBackground : colors.cardBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(selected ? Color.clear : colors.pillSecondaryBorder, lineWidth: selected ? 0 : CursorMetrics.pillButtonBorderWidth)
            )
        }
        .buttonStyle(.plain)
        .disabled(s.isAnswered)
        .accessibilityIdentifier("question-option-\(opt.label)")
    }

    private func freeTextField(
        s: QuestionCardModel.PresentationState,
        item: QuestionCardModel.ItemState,
        idx: Int
    ) -> some View {
        let placeholder = item.options.isEmpty ? "Your answer…" : "Or type your own answer…"
        return TextField(placeholder, text: Binding(
            get: { item.freeText },
            set: { text in
                guard var updated = state else { return }
                QuestionCardModel.setFreeText(in: &updated, itemIndex: idx, text: text)
                state = updated
            }
        ), axis: .vertical)
        .font(CursorType.bodyText)
        .foregroundColor(colors.primaryText)
        .disabled(s.isAnswered)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(colors.hairline, lineWidth: 0.75)
        )
        .lineLimit(3...6)
        .accessibilityIdentifier("question-freetext-\(idx)")
    }

    // MARK: - Submit / answered footer

    private func submitSection(_ s: QuestionCardModel.PresentationState) -> some View {
        let ready = QuestionCardModel.isReadyToAnswer(s)
        return VStack(spacing: 0) {
            CursorPillButton(title: "Submit answer", style: .primary, fullWidth: true) {
                guard var updated = state, QuestionCardModel.isReadyToAnswer(updated) else { return }
                let answer = QuestionCardModel.buildAnswer(from: updated)
                updated.isAnswered = true
                updated.submittedAnswer = answer
                state = updated
                onAnswer(answer)
            }
            .opacity(ready ? 1 : 0.4)
            .disabled(!ready)
            .accessibilityIdentifier("question-submit")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func answeredFooter(_ s: QuestionCardModel.PresentationState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Answered".uppercased())
                .font(CursorType.sectionHeader)
                .tracking(0.5)
                .foregroundColor(colors.mutedText)
            ForEach(Array(s.items.enumerated()), id: \.offset) { _, item in
                Text(QuestionCardModel.answeredSummary(for: item))
                    .font(CursorType.bodyText)
                    .foregroundColor(colors.secondaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityIdentifier("question-answered-footer")
    }

    // MARK: - Helpers

    private var sectionDivider: some View {
        CursorHairlineDivider()
    }
}

// MARK: - FlowLayout

/// Simple wrapping horizontal flow layout for option chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxHeight = max(maxHeight, currentY + rowHeight)
        }
        return CGSize(width: width, height: maxHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
#endif
