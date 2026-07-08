#if os(iOS)
import SwiftUI
import DesignSystem
import LancerCore

/// Cursor-style expanded composer: floating card with repo/branch picker, run
/// target, multiline prompt, optional contract disclosure, and attach / model /
/// dictate controls.
public struct CursorComposerSheet: View {
    public struct SendPayload: Sendable {
        public let prompt: String
        public let contract: ProofReceipt.Contract?

        public init(prompt: String, contract: ProofReceipt.Contract?) {
            self.prompt = prompt
            self.contract = contract
        }
    }

    @Environment(\.cursorScheme) private var cursorScheme
    @FocusState private var isPromptFocused: Bool
    @State private var text: String = ""
    @State private var contractExpanded: Bool = false
    @State private var contractGoal: String = ""
    @State private var doneCriteria: [String] = [""]
    @State private var validationCommands: [String] = [""]
    @State private var showingContextSheet: Bool = false

    /// Pass `threadID` to enable draft persistence: the draft is loaded on appear,
    /// saved on every text change, and cleared when the prompt is sent.
    private let threadID: String?
    private let repoName: String
    private let branchName: String
    private let modelName: String
    private let placeholder: String
    private let prefillText: String?
    private let onPickRepo: () -> Void
    private let onPickRunTarget: () -> Void
    private let onAttach: () -> Void
    private let onPickModel: () -> Void
    private let onDictate: () -> Void
    private let onSend: ((SendPayload) -> Void)?

    private static let maxDoneCriteria = 8
    private static let maxValidationCommands = 4
    private static let maxCriterionLength = 200

    public init(
        threadID: String? = nil,
        repoName: String = "lancer-ios",
        branchName: String = "main",
        modelName: String = "Composer 2.5",
        placeholder: String = "Plan, ask, build...",
        prefillText: String? = nil,
        onPickRepo: @escaping () -> Void = {},
        onPickRunTarget: @escaping () -> Void = {},
        onAttach: @escaping () -> Void = {},
        onPickModel: @escaping () -> Void = {},
        onDictate: @escaping () -> Void = {},
        onSend: ((SendPayload) -> Void)? = nil
    ) {
        self.threadID = threadID
        self.repoName = repoName
        self.branchName = branchName
        self.modelName = modelName
        self.placeholder = placeholder
        self.prefillText = prefillText
        self.onPickRepo = onPickRepo
        self.onPickRunTarget = onPickRunTarget
        self.onAttach = onAttach
        self.onPickModel = onPickModel
        self.onDictate = onDictate
        self.onSend = onSend
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        ZStack {
            colors.background.opacity(cursorScheme == .light ? 0.55 : 0.72)
                .ignoresSafeArea()

            CursorFloatingCard {
                VStack(spacing: 0) {
                    Capsule()
                        .fill(colors.mutedText.opacity(0.55))
                        .frame(width: CursorMetrics.sheetDragHandleWidth, height: CursorMetrics.sheetDragHandleHeight)
                        .padding(.top, 10)
                        .padding(.bottom, 14)

                    HStack(spacing: CursorMetrics.composerSheetPickerSpacing) {
                        Button(action: onPickRepo) {
                            HStack(spacing: 4) {
                                Text(repoName)
                                    .foregroundColor(colors.primaryText)
                                Text(branchName)
                                    .foregroundColor(colors.secondaryText)
                                chevronDown(colors)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 8)

                        Button(action: onPickRunTarget) {
                            HStack(spacing: 4) {
                                Image(systemName: "cloud")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(colors.secondaryText)
                                chevronDown(colors)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("cloud")
                    }
                    .font(CursorType.rowTitle)
                    .padding(.horizontal, CursorMetrics.sheetHeaderHorizontalPadding)
                    .padding(.bottom, CursorMetrics.composerSheetPickerBottomPadding)

                    contractDisclosure(colors: colors)

                    TextField(placeholder, text: $text, axis: .vertical)
                        .font(CursorType.composerPlaceholder)
                        .foregroundColor(colors.primaryText)
                        .tint(colors.statusDotActive)
                        .lineLimit(4...12)
                        .focused($isPromptFocused)
                        .frame(minHeight: CursorMetrics.composerSheetTextMinHeight, alignment: .top)
                        .padding(.horizontal, CursorMetrics.sheetHeaderHorizontalPadding)
                        .padding(.bottom, CursorMetrics.composerSheetTextBottomPadding)
                        .onSubmit { submitIfNeeded() }

                    HStack(spacing: CursorMetrics.composerSheetBottomRowSpacing) {
                        CursorIconButton(
                            systemImageName: "plus",
                            diameter: CursorMetrics.composerToolbarButtonDiameter,
                            action: {
                                onAttach()
                                showingContextSheet = true
                            }
                        )
                        .accessibilityIdentifier("composer.plus")

                        modelPickerButton(colors: colors)

                        Spacer(minLength: 8)

                        if onSend != nil {
                            CursorIconButton(
                                systemImageName: "arrow.up.circle.fill",
                                diameter: CursorMetrics.composerToolbarButtonDiameter,
                                action: submitIfNeeded
                            )
                            .accessibilityIdentifier("composer.send")
                            .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        } else {
                            CursorIconButton(
                                systemImageName: "photo",
                                diameter: CursorMetrics.composerToolbarButtonDiameter,
                                action: onAttach
                            )
                            .accessibilityIdentifier("composer.attach")
                        }

                        CursorIconButton(
                            systemImageName: "mic",
                            diameter: CursorMetrics.composerToolbarButtonDiameter,
                            action: onDictate
                        )
                    }
                    .padding(.horizontal, CursorMetrics.sheetHeaderHorizontalPadding)
                    .padding(.bottom, CursorMetrics.composerSheetBottomRowBottomPadding)
                }
            }
            .padding(.horizontal, CursorMetrics.floatingCardHorizontalMargin)
            .padding(.bottom, 8)
        }
        .onAppear {
            isPromptFocused = true
            if let prefillText, !prefillText.isEmpty {
                text = prefillText
            } else if let id = threadID {
                let draft = CursorComposerDraftStore.shared.loadDraft(threadID: id)
                if !draft.isEmpty { text = draft }
                let contractDraft = CursorComposerDraftStore.shared.loadContractDraft(threadID: id)
                contractExpanded = contractDraft.isExpanded
                contractGoal = contractDraft.goal
                doneCriteria = contractDraft.doneCriteria.isEmpty ? [""] : contractDraft.doneCriteria
                validationCommands = contractDraft.validationCommands.isEmpty ? [""] : contractDraft.validationCommands
            }
        }
        .onChange(of: text) { _, newValue in
            persistDrafts(prompt: newValue)
        }
        .onChange(of: contractExpanded) { _, _ in persistDrafts(prompt: text) }
        .onChange(of: contractGoal) { _, _ in persistDrafts(prompt: text) }
        .onChange(of: doneCriteria) { _, _ in persistDrafts(prompt: text) }
        .onChange(of: validationCommands) { _, _ in persistDrafts(prompt: text) }
        .sheet(isPresented: $showingContextSheet) {
            CursorContextSheet(onClose: { showingContextSheet = false })
        }
    }

    @ViewBuilder
    private func contractDisclosure(colors: CursorColors) -> some View {
        DisclosureGroup(isExpanded: $contractExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                contractField(
                    title: "Goal",
                    placeholder: "Defaults to first line of prompt",
                    text: $contractGoal,
                    colors: colors
                )

                contractListSection(
                    title: "Done criteria",
                    placeholder: "Criterion",
                    rows: $doneCriteria,
                    maxRows: Self.maxDoneCriteria,
                    colors: colors
                )

                contractListSection(
                    title: "Validation commands",
                    placeholder: "e.g. swift test",
                    rows: $validationCommands,
                    maxRows: Self.maxValidationCommands,
                    colors: colors,
                    monospaced: true
                )
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
        } label: {
            Text("Contract")
                .font(CursorType.rowSecondary)
                .foregroundColor(colors.secondaryText)
        }
        .padding(.horizontal, CursorMetrics.sheetHeaderHorizontalPadding)
        .padding(.bottom, 10)
        .accessibilityIdentifier("composer.contract")
    }

    @ViewBuilder
    private func contractField(
        title: String, placeholder: String, text: Binding<String>, colors: CursorColors
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(CursorType.rowSecondary)
                .foregroundColor(colors.mutedText)
            TextField(placeholder, text: text)
                .font(CursorType.composerPlaceholder)
                .foregroundColor(colors.primaryText)
                .textFieldStyle(.plain)
        }
    }

    @ViewBuilder
    private func contractListSection(
        title: String,
        placeholder: String,
        rows: Binding<[String]>,
        maxRows: Int,
        colors: CursorColors,
        monospaced: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(CursorType.rowSecondary)
                    .foregroundColor(colors.mutedText)
                Spacer()
                if rows.wrappedValue.count < maxRows {
                    Button("Add") { rows.wrappedValue.append("") }
                        .font(CursorType.rowSecondary)
                        .foregroundColor(colors.statusDotActive)
                }
            }
            ForEach(rows.wrappedValue.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    TextField(placeholder, text: rows[index])
                        .font(monospaced ? CursorType.inlineCode : CursorType.composerPlaceholder)
                        .foregroundColor(colors.primaryText)
                        .textFieldStyle(.plain)
                        .onChange(of: rows.wrappedValue[index]) { _, newValue in
                            if newValue.count > Self.maxCriterionLength {
                                rows.wrappedValue[index] = String(newValue.prefix(Self.maxCriterionLength))
                            }
                        }
                    if rows.wrappedValue.count > 1 {
                        Button {
                            rows.wrappedValue.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(colors.mutedText)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func modelPickerButton(colors: CursorColors) -> some View {
        Button(action: onPickModel) {
            HStack(spacing: 6) {
                Text(modelName)
                    .font(CursorType.pillLabel)
                    .foregroundColor(colors.primaryText)
                chevronDown(colors)
            }
            .padding(.horizontal, cursorScheme == .light ? CursorMetrics.pillButtonHorizontalPadding : 0)
            .frame(height: CursorMetrics.composerToolbarButtonDiameter)
            .background {
                if cursorScheme == .light {
                    Capsule().fill(colors.composerBackground)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func chevronDown(_ colors: CursorColors) -> some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(colors.mutedText)
    }

    private func persistDrafts(prompt: String) {
        guard let id = threadID else { return }
        if prompt.isEmpty
            && contractGoal.isEmpty
            && doneCriteria.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            && validationCommands.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            && !contractExpanded {
            CursorComposerDraftStore.shared.clearDraft(threadID: id)
        } else {
            if prompt.isEmpty {
                CursorComposerDraftStore.shared.saveDraft(threadID: id, text: "")
            } else {
                CursorComposerDraftStore.shared.saveDraft(threadID: id, text: prompt)
            }
            CursorComposerDraftStore.shared.saveContractDraft(
                threadID: id,
                contract: CursorComposerDraftStore.ContractDraft(
                    goal: contractGoal,
                    doneCriteria: doneCriteria,
                    validationCommands: validationCommands,
                    isExpanded: contractExpanded
                )
            )
        }
    }

    private func submitIfNeeded() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let id = threadID {
            CursorComposerDraftStore.shared.clearDraft(threadID: id)
        }
        onSend?(SendPayload(prompt: trimmed, contract: resolvedContract(for: trimmed)))
        text = ""
        contractGoal = ""
        doneCriteria = [""]
        validationCommands = [""]
        contractExpanded = false
    }

    /// Builds a wire contract when the user supplied criteria, commands, or an
    /// explicit goal. Goal defaults to the prompt's first line when omitted.
    static func resolvedContract(
        prompt: String,
        goal: String,
        doneCriteria: [String],
        validationCommands: [String]
    ) -> ProofReceipt.Contract? {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let criteria = doneCriteria
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(maxDoneCriteria)
        let commands = validationCommands
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(maxValidationCommands)
        guard !criteria.isEmpty || !commands.isEmpty || !trimmedGoal.isEmpty else { return nil }
        let effectiveGoal = trimmedGoal.isEmpty ? firstLine(of: prompt) : trimmedGoal
        guard !effectiveGoal.isEmpty else { return nil }
        return ProofReceipt.Contract(
            goal: effectiveGoal,
            doneCriteria: Array(criteria),
            validationCommands: Array(commands)
        )
    }

    private func resolvedContract(for prompt: String) -> ProofReceipt.Contract? {
        Self.resolvedContract(
            prompt: prompt,
            goal: contractGoal,
            doneCriteria: doneCriteria,
            validationCommands: validationCommands
        )
    }

    private static func firstLine(of prompt: String) -> String {
        prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
    }
}
#endif
