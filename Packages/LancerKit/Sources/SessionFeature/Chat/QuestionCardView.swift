#if os(iOS)
import SwiftUI
import LancerCore
import DesignSystem

/// Chat-thread card that renders a `QuestionEvent` from the daemon and lets the
/// user select options (Ladder) and/or enter free text, then submit an answer.
///
/// Visual contract:
/// - Left gutter accent: `t.termAccent` while pending, `t.termOk` once answered.
/// - Header: "Question › agent" label (same mono style as ReceiptCardView), plus
///   a "Best effort" badge when `confidence == "bestEffort"`.
/// - Each `QuestionItem` shows as a labeled option row (tappable DSChip-style
///   buttons); multi-select items allow multiple choices.
/// - A free-text field appears when `allowFreeText` is true (always for
///   bestEffort / options-less items).
/// - "Submit answer" button, enabled only when `isReadyToAnswer`.
/// - Answered state: gutter turns green, options/free-text become read-only,
///   the submitted selection is shown.
public struct QuestionCardView: View {
    let artifact: ChatArtifact
    let onAnswer: (QuestionAnswerParams) -> Void

    @State private var state: QuestionCardModel.PresentationState?
    @Environment(\.lancerTokens) private var t

    public init(
        artifact: ChatArtifact,
        initialState: QuestionCardModel.PresentationState? = nil,
        onAnswer: @escaping (QuestionAnswerParams) -> Void
    ) {
        self.artifact = artifact
        self.onAnswer = onAnswer
        self._state = State(initialValue: initialState ?? QuestionCardModel.decode(from: artifact))
    }

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
        .background(t.termSurface)
        .clipShape(RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous)
                .strokeBorder(s.isAnswered ? t.termOk.opacity(0.35) : t.termBorder, lineWidth: 0.75)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("question-card")
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    // MARK: - Gutter

    private func gutterBar(answered: Bool) -> some View {
        Rectangle()
            .fill(answered ? t.termOk.opacity(0.55) : t.termAccent)
            .frame(width: 3)
    }

    // MARK: - Header

    private func header(_ s: QuestionCardModel.PresentationState) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Question")
                        .foregroundStyle(t.termText2)
                        .fontWeight(.semibold)
                    Text("›")
                        .foregroundStyle(t.termText3)
                    Text(s.agent)
                        .foregroundStyle(t.termText3)
                }
                .font(.dsMonoPt(10))
                .tracking(10 * 0.12)
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
            .font(.dsMonoPt(10, weight: .semibold))
            .foregroundStyle(t.termText2)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(t.termSurface2)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(t.termBorder, lineWidth: 0.5))
            .accessibilityIdentifier("question-best-effort-badge")
    }

    private var answeredBadge: some View {
        HStack(spacing: 4) {
            DSIconView(.check, size: 11, color: t.ok)
            Text("Answered")
                .font(.dsMonoPt(10, weight: .semibold))
        }
        .foregroundStyle(t.ok)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(t.okSoft)
        .clipShape(Capsule())
        .accessibilityIdentifier("question-answered-badge")
    }

    // MARK: - Item section

    private func itemSection(s: QuestionCardModel.PresentationState, item: QuestionCardModel.ItemState, idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let header = item.header, !header.isEmpty {
                Text(header.uppercased())
                    .font(.dsMonoPt(10))
                    .tracking(10 * 0.12)
                    .foregroundStyle(t.termText3)
            }

            Text(item.question)
                .font(.dsMonoPt(13))
                .foregroundStyle(t.termText)
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
                    .font(.dsMonoPt(12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? t.accentFg : t.termText)
                if let desc = opt.description, !desc.isEmpty {
                    Text(desc)
                        .font(.dsMonoPt(10))
                        .foregroundStyle(selected ? t.accentFg.opacity(0.8) : t.termText3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(selected ? t.termAccent : t.termSurface2)
            .clipShape(RoundedRectangle(cornerRadius: t.radiusSM, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.radiusSM, style: .continuous)
                    .strokeBorder(selected ? t.termAccent : t.termBorder, lineWidth: selected ? 0 : 0.75)
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
        .font(.dsMonoPt(12))
        .foregroundStyle(t.termText)
        .disabled(s.isAnswered)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(t.termSurface2)
        .clipShape(RoundedRectangle(cornerRadius: t.radiusSM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.radiusSM, style: .continuous)
                .strokeBorder(t.termBorder, lineWidth: 0.75)
        )
        .lineLimit(3...6)
        .accessibilityIdentifier("question-freetext-\(idx)")
    }

    // MARK: - Submit / answered footer

    private func submitSection(_ s: QuestionCardModel.PresentationState) -> some View {
        let ready = QuestionCardModel.isReadyToAnswer(s)
        return VStack(spacing: 0) {
            Button {
                guard var updated = state, QuestionCardModel.isReadyToAnswer(updated) else { return }
                let answer = QuestionCardModel.buildAnswer(from: updated)
                updated.isAnswered = true
                updated.submittedAnswer = answer
                state = updated
                onAnswer(answer)
            } label: {
                Text("Submit answer")
                    .font(.dsMonoPt(12, weight: .semibold))
                    .foregroundStyle(t.accentFg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(ready ? t.termAccent : t.termAccent.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: t.radiusSM, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!ready)
            .accessibilityIdentifier("question-submit")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func answeredFooter(_ s: QuestionCardModel.PresentationState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Answered".uppercased())
                .font(.dsMonoPt(10))
                .tracking(10 * 0.12)
                .foregroundStyle(t.termText3)
            ForEach(Array(s.items.enumerated()), id: \.offset) { _, item in
                Text(QuestionCardModel.answeredSummary(for: item))
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.termText2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityIdentifier("question-answered-footer")
    }

    // MARK: - Helpers

    private var sectionDivider: some View {
        Rectangle().fill(t.termBorder).frame(height: 1)
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
