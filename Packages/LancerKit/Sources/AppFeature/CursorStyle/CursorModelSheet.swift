#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit

/// Cursor-style "Model" picker sheet: a search field below the title, an
/// "Active" section for the currently selected model, and a "More" section
/// listing the other vendor models Lancer can dispatch to. Each row has a
/// trailing "..." menu button; the active row also shows a checkmark.
public struct CursorModelSheet: View {
    /// One selectable model row.
    public struct CursorModelOption: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let isSelected: Bool

        public init(id: String, title: String, isSelected: Bool = false) {
            self.id = id
            self.title = title
            self.isSelected = isSelected
        }
    }

    @Environment(\.cursorScheme) private var cursorScheme
    @State private var searchText: String = ""

    private let activeModels: [CursorModelOption]
    private let moreModels: [CursorModelOption]
    private let onClose: () -> Void
    private let onSelect: (CursorModelOption) -> Void
    private let onOptions: (CursorModelOption) -> Void

    public init(
        activeModels: [CursorModelOption] = [
            CursorModelOption(id: ManagedModel.claudeHaiku.rawValue, title: ManagedModel.claudeHaiku.label, isSelected: true)
        ],
        moreModels: [CursorModelOption] = [
            CursorModelOption(id: ManagedModel.claudeSonnet.rawValue, title: ManagedModel.claudeSonnet.label),
            CursorModelOption(id: ManagedModel.claudeOpus.rawValue, title: ManagedModel.claudeOpus.label),
            CursorModelOption(id: ManagedModel.gptCodex.rawValue, title: ManagedModel.gptCodex.label),
            CursorModelOption(id: ManagedModel.gpt.rawValue, title: ManagedModel.gpt.label),
            CursorModelOption(id: ManagedModel.geminiPro.rawValue, title: ManagedModel.geminiPro.label)
        ],
        onClose: @escaping () -> Void = {},
        onSelect: @escaping (CursorModelOption) -> Void = { _ in },
        onOptions: @escaping (CursorModelOption) -> Void = { _ in }
    ) {
        self.activeModels = activeModels
        self.moreModels = moreModels
        self.onClose = onClose
        self.onSelect = onSelect
        self.onOptions = onOptions
    }

    private var filteredMoreModels: [CursorModelOption] {
        guard !searchText.isEmpty else { return moreModels }
        return moreModels.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    public var body: some View {
        CursorBottomSheetContainer(
            title: "Model",
            leadingButton: (systemImageName: "xmark", action: onClose)
        ) {
            VStack(spacing: 0) {
                CursorSearchField(text: $searchText)
                    .padding(.bottom, CursorMetrics.sectionHeaderTopPadding)

                CursorSectionHeader("Active")
                ForEach(activeModels) { model in
                    row(for: model)
                }

                CursorSectionHeader("More")
                ForEach(filteredMoreModels) { model in
                    row(for: model)
                }
            }
            .padding(.bottom, CursorMetrics.sheetContentBottomPadding)
        }
    }

    private func row(for model: CursorModelOption) -> some View {
        let colors = CursorColors.resolve(cursorScheme)
        return VStack(spacing: 0) {
            HStack(spacing: CursorMetrics.rowSpacing) {
                Text(model.title)
                    .font(CursorType.rowTitle)
                    .foregroundColor(colors.primaryText)
                Spacer()
                CursorIconButton(
                    systemImageName: "ellipsis",
                    diameter: CursorMetrics.modelRowEllipsisDiameter
                ) {
                    onOptions(model)
                }
                if model.isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(colors.primaryText)
                }
            }
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
            .padding(.vertical, CursorMetrics.rowVerticalPadding)
            Rectangle()
                .fill(colors.hairline)
                .frame(height: CursorMetrics.rowHairlineHeight)
                .padding(.leading, CursorMetrics.rowHorizontalPadding)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(model)
        }
    }
}
#endif
