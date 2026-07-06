#if os(iOS)
import SwiftUI

/// Cursor-style expanded composer sheet: a repo/branch picker and a run-target
/// picker on top, a multiline prompt field, and a bottom row of attach /
/// model / dictate controls. Visual clone of Cursor's mobile composer sheet
/// (repo picker "lancer-ios main", cloud run-target picker, "Composer 2.5"
/// model pill) — presentation/wiring (tap-to-expand, `.sheet`) is added by a
/// later pass.
public struct CursorComposerSheet: View {
    @Environment(\.cursorScheme) private var cursorScheme
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
        CursorBottomSheetContainer(title: "") {
            VStack(spacing: 0) {
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

                    Spacer()
                }
                .font(CursorType.rowTitle)
                .padding(.horizontal, CursorMetrics.sheetHeaderHorizontalPadding)
                .padding(.bottom, CursorMetrics.composerSheetPickerBottomPadding)

                TextField(placeholder, text: $text, axis: .vertical)
                    .font(CursorType.composerPlaceholder)
                    .foregroundColor(colors.primaryText)
                    .tint(colors.primaryText)
                    .lineLimit(3...8)
                    .frame(minHeight: CursorMetrics.composerSheetTextMinHeight, alignment: .top)
                    .padding(.horizontal, CursorMetrics.sheetHeaderHorizontalPadding)
                    .padding(.bottom, CursorMetrics.composerSheetTextBottomPadding)
                    .onSubmit { submitIfNeeded() }

                HStack(spacing: CursorMetrics.composerSheetBottomRowSpacing) {
                    CursorIconButton(systemImageName: "plus", action: onAttach)

                    Button(action: onPickModel) {
                        HStack(spacing: 6) {
                            Text(modelName)
                                .font(CursorType.pillLabel)
                                .foregroundColor(colors.primaryText)
                            chevronDown(colors)
                        }
                        .padding(.horizontal, CursorMetrics.pillButtonHorizontalPadding)
                        .frame(height: CursorMetrics.pillButtonHeight)
                        .background(Capsule().fill(colors.composerBackground))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if onSend != nil {
                        CursorIconButton(systemImageName: "arrow.up.circle.fill", action: submitIfNeeded)
                    }

                    CursorIconButton(systemImageName: "mic.fill", action: onDictate)
                }
                .padding(.horizontal, CursorMetrics.sheetHeaderHorizontalPadding)
                .padding(.bottom, CursorMetrics.composerSheetBottomRowBottomPadding)
            }
        }
        .environment(\.cursorScheme, .light)
    }

    private func chevronDown(_ colors: CursorColors) -> some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(colors.secondaryText)
    }

    private func submitIfNeeded() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend?(trimmed)
        text = ""
    }
}
#endif
