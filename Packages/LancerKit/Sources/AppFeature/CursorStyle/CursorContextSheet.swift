#if os(iOS)
import SwiftUI
import DesignSystem

/// Cursor-style "Context" sheet, presented from the composer's "+" button
/// (`CursorComposerSheet`) only. Layout mirrors the reference (IMG_2421/2422):
/// an optional horizontal carousel of recent screenshot thumbnails, a "Mode"
/// list (Plan / Draft), and an "Add" list (Photos, Screenshots, Camera,
/// Files, MCP Servers).
///
/// Lancer has no real screenshot-capture ledger yet, so `thumbnails` defaults
/// to empty and the carousel is simply omitted rather than showing fabricated
/// images — see the A3-R3 report for the wiring gap.
public struct CursorContextSheet: View {
    public enum Mode: String, CaseIterable, Sendable {
        case plan
        case draft

        var title: String {
            switch self {
            case .plan: return "Plan"
            case .draft: return "Draft"
            }
        }

        var iconSystemName: String {
            switch self {
            case .plan: return "checklist"
            case .draft: return "circle.dashed"
            }
        }
    }

    /// One recent-screenshot thumbnail in the carousel.
    public struct Thumbnail: Identifiable, Sendable {
        public let id: String
        public let systemImageName: String

        public init(id: String, systemImageName: String = "photo") {
            self.id = id
            self.systemImageName = systemImageName
        }
    }

    @Environment(\.cursorScheme) private var cursorScheme
    @State private var selectedMode: Mode

    private let thumbnails: [Thumbnail]
    private let mcpServerCount: Int
    private let onClose: () -> Void
    private let onSelectMode: (Mode) -> Void
    private let onPhotos: () -> Void
    private let onScreenshots: () -> Void
    private let onCamera: () -> Void
    private let onFiles: () -> Void
    private let onMCPServers: () -> Void

    public init(
        thumbnails: [Thumbnail] = [],
        mcpServerCount: Int = 0,
        initialMode: Mode = .plan,
        onClose: @escaping () -> Void = {},
        onSelectMode: @escaping (Mode) -> Void = { _ in },
        onPhotos: @escaping () -> Void = {},
        onScreenshots: @escaping () -> Void = {},
        onCamera: @escaping () -> Void = {},
        onFiles: @escaping () -> Void = {},
        onMCPServers: @escaping () -> Void = {}
    ) {
        self.thumbnails = thumbnails
        self.mcpServerCount = mcpServerCount
        self._selectedMode = State(initialValue: initialMode)
        self.onClose = onClose
        self.onSelectMode = onSelectMode
        self.onPhotos = onPhotos
        self.onScreenshots = onScreenshots
        self.onCamera = onCamera
        self.onFiles = onFiles
        self.onMCPServers = onMCPServers
    }

    public var body: some View {
        CursorBottomSheetContainer(
            title: "Context",
            leadingButton: (systemImageName: "xmark", action: onClose)
        ) {
            VStack(spacing: 0) {
                if !thumbnails.isEmpty {
                    thumbnailCarousel
                        .padding(.bottom, 8)
                }

                CursorSectionHeader("Mode")
                ForEach(Mode.allCases, id: \.self) { mode in
                    modeRow(mode)
                }

                CursorSectionHeader("Add")
                addRow(iconSystemName: "photo", title: "Photos", action: onPhotos)
                addRow(iconSystemName: "viewfinder", title: "Screenshots", showChevron: true, action: onScreenshots)
                addRow(iconSystemName: "camera", title: "Camera", action: onCamera)
                addRow(iconSystemName: "folder", title: "Files", action: onFiles)
                addRow(
                    iconSystemName: "paperclip",
                    title: "MCP Servers",
                    trailingCount: mcpServerCount,
                    showChevron: true,
                    action: onMCPServers
                )
            }
            .padding(.bottom, CursorMetrics.sheetContentBottomPadding)
        }
        .accessibilityIdentifier("context.sheet")
    }

    private var thumbnailCarousel: some View {
        let colors = CursorColors.resolve(cursorScheme)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(thumbnails) { thumbnail in
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colors.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(colors.hairline, lineWidth: 0.5)
                        )
                        .overlay(
                            Image(systemName: thumbnail.systemImageName)
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(colors.mutedText)
                        )
                        .frame(width: 96, height: 128)
                }
            }
            .padding(.horizontal, CursorMetrics.sheetHeaderHorizontalPadding)
        }
        .accessibilityIdentifier("context.thumbnails")
    }

    private func modeRow(_ mode: Mode) -> some View {
        let colors = CursorColors.resolve(cursorScheme)
        return Button {
            selectedMode = mode
            onSelectMode(mode)
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: CursorMetrics.rowSpacing) {
                    Image(systemName: mode.iconSystemName)
                        .font(.system(size: CursorMetrics.rowIconSize - 6, weight: .regular))
                        .foregroundColor(colors.secondaryText)
                        .frame(width: CursorMetrics.rowIconSize, height: CursorMetrics.rowIconSize)
                    Text(mode.title)
                        .font(CursorType.rowTitle)
                        .foregroundColor(colors.primaryText)
                    Spacer()
                    if selectedMode == mode {
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
                    .padding(.leading, CursorMetrics.rowHairlineLeadingInsetWithIcon)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("context.mode.\(mode.rawValue)")
    }

    private func addRow(
        iconSystemName: String,
        title: String,
        trailingCount: Int? = nil,
        showChevron: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            CursorListRow(
                iconSystemName: iconSystemName,
                title: title,
                trailingCount: trailingCount,
                showChevron: showChevron
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("context.add.\(title.lowercased())")
    }
}
#endif
