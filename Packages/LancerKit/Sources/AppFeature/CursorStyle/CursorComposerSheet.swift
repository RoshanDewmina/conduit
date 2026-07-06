#if os(iOS)
import SwiftUI
import DesignSystem

/// Cursor-style expanded composer: floating card with repo/branch picker, run
/// target, multiline prompt, and attach / model / dictate controls.
public struct CursorComposerSheet: View {
    @Environment(\.cursorScheme) private var cursorScheme
    @FocusState private var isPromptFocused: Bool
    @State private var text: String = ""

    private let repoName: String
    private let branchName: String
    private let modelName: String
    private let placeholder: String
    private let onPickRepo: () -> Void
    private let onPickRunTarget: () -> Void
    private let onAttach: () -> Void
    private let onPickModel: () -> Void
    private let onDictate: () -> Void
    private let onSend: ((String) -> Void)?

    public init(
        repoName: String = "lancer-ios",
        branchName: String = "main",
        modelName: String = "Composer 2.5",
        placeholder: String = "Plan, ask, build...",
        onPickRepo: @escaping () -> Void = {},
        onPickRunTarget: @escaping () -> Void = {},
        onAttach: @escaping () -> Void = {},
        onPickModel: @escaping () -> Void = {},
        onDictate: @escaping () -> Void = {},
        onSend: ((String) -> Void)? = nil
    ) {
        self.repoName = repoName
        self.branchName = branchName
        self.modelName = modelName
        self.placeholder = placeholder
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
                            action: onAttach
                        )

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
        .onAppear { isPromptFocused = true }
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

    private func submitIfNeeded() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend?(trimmed)
        text = ""
    }
}
#endif
