#if os(iOS)
import SwiftUI

/// Self-contained visual language cloned from Cursor's mobile app, measured off
/// real screenshots. Intentionally does not import `DesignSystem` — this is a
/// separate light-mode-only look, distinct from Lancer's branded dark theme.
public enum CursorPalette {
    public static let pageBackground = Color(red: 0.961, green: 0.957, blue: 0.941)
    public static let sheetBackground = Color.white
    public static let composerBackground = Color(red: 0.918, green: 0.914, blue: 0.898)
    public static let iconButtonBackground = Color.white
    public static let iconButtonBorder = Color.black.opacity(0.08)
    public static let primaryText = Color.black
    public static let secondaryText = Color(white: 0.55)
    public static let mutedText = Color(white: 0.68)
    public static let hairline = Color.black.opacity(0.08)
    public static let statusDotActive = Color(red: 0.20, green: 0.47, blue: 0.93)
    public static let statusDotIdle = Color(white: 0.82)
    public static let successGreen = Color(red: 0.16, green: 0.55, blue: 0.30)
    public static let dangerRed = Color(red: 0.75, green: 0.20, blue: 0.20)
}

public enum CursorType {
    public static let pageTitle = Font.system(size: 32, weight: .bold)
    public static let sheetTitle = Font.system(size: 17, weight: .semibold)
    public static let rowTitle = Font.system(size: 17, weight: .regular)
    public static let rowSecondary = Font.system(size: 13, weight: .regular)
    public static let sectionHeader = Font.system(size: 13, weight: .regular)
    public static let composerPlaceholder = Font.system(size: 16, weight: .regular)
}

/// 44pt circular icon button with a hairline border, matching Cursor's header
/// affordances (search, add, etc).
public struct CursorIconButton: View {
    private let systemImageName: String
    private let action: () -> Void

    public init(systemImageName: String, action: @escaping () -> Void) {
        self.systemImageName = systemImageName
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(CursorPalette.iconButtonBackground)
                    .overlay(
                        Circle().stroke(CursorPalette.iconButtonBorder, lineWidth: 1)
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: systemImageName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(CursorPalette.primaryText)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Header row: arbitrary leading content on the left, a row of `CursorIconButton`s
/// on the right. Kept concrete (AnyView + array of icon buttons) rather than
/// generic to stay simple and compile cleanly.
public struct CursorHeaderBar: View {
    private let leading: AnyView
    private let trailing: [CursorIconButton]

    public init(leading: AnyView, trailing: [CursorIconButton]) {
        self.leading = leading
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: 12) {
            leading
            Spacer()
            ForEach(Array(trailing.enumerated()), id: \.offset) { _, button in
                button
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

/// A simple list row: optional leading icon, title, optional trailing count
/// badge, optional chevron, with a bottom hairline divider inset to the title.
public struct CursorListRow: View {
    private let iconSystemName: String?
    private let title: String
    private let trailingCount: Int?
    private let showChevron: Bool

    public init(
        iconSystemName: String? = nil,
        title: String,
        trailingCount: Int? = nil,
        showChevron: Bool = false
    ) {
        self.iconSystemName = iconSystemName
        self.title = title
        self.trailingCount = trailingCount
        self.showChevron = showChevron
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let iconSystemName {
                    Image(systemName: iconSystemName)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(CursorPalette.secondaryText)
                        .frame(width: 24, height: 24)
                }
                Text(title)
                    .font(CursorType.rowTitle)
                    .foregroundColor(CursorPalette.primaryText)
                Spacer()
                if let trailingCount {
                    Text("\(trailingCount)")
                        .font(CursorType.rowSecondary)
                        .foregroundColor(CursorPalette.secondaryText)
                }
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(CursorPalette.mutedText)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            Rectangle()
                .fill(CursorPalette.hairline)
                .frame(height: 1)
                .padding(.leading, iconSystemName != nil ? 52 : 16)
        }
    }
}

/// Status line under a thread row title: either a green "Checks Passed" with a
/// colored diffstat, or a plain gray "No Changes".
public enum CursorThreadStatus {
    case checksPassed(diffAdded: Int, diffRemoved: Int)
    case noChanges
}

public struct CursorThreadRowModel: Identifiable {
    public let id: UUID
    public let title: String
    public let repoName: String
    public let isActive: Bool
    public let statusLine: CursorThreadStatus

    public init(
        id: UUID = UUID(),
        title: String,
        repoName: String,
        isActive: Bool,
        statusLine: CursorThreadStatus
    ) {
        self.id = id
        self.title = title
        self.repoName = repoName
        self.isActive = isActive
        self.statusLine = statusLine
    }
}

/// One thread row: leading status dot, title, secondary status line, optional
/// repo-name pill (used on Home, which spans repos), hairline divider.
public struct CursorThreadRow: View {
    private let model: CursorThreadRowModel
    private let showRepoTag: Bool

    public init(model: CursorThreadRowModel, showRepoTag: Bool = false) {
        self.model = model
        self.showRepoTag = showRepoTag
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(model.isActive ? CursorPalette.statusDotActive : CursorPalette.statusDotIdle)
                    .frame(width: 9, height: 9)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.title)
                        .font(CursorType.rowTitle)
                        .foregroundColor(CursorPalette.primaryText)

                    HStack(spacing: 6) {
                        statusLineView
                        if showRepoTag {
                            repoTag
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Rectangle()
                .fill(CursorPalette.hairline)
                .frame(height: 1)
                .padding(.leading, 37)
        }
    }

    @ViewBuilder
    private var statusLineView: some View {
        switch model.statusLine {
        case .checksPassed(let diffAdded, let diffRemoved):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CursorPalette.successGreen)
                Text("Checks Passed")
                    .font(CursorType.rowSecondary)
                    .foregroundColor(CursorPalette.secondaryText)
                Text("+\(diffAdded)")
                    .font(CursorType.rowSecondary)
                    .foregroundColor(CursorPalette.successGreen)
                Text("-\(diffRemoved)")
                    .font(CursorType.rowSecondary)
                    .foregroundColor(CursorPalette.dangerRed)
            }
        case .noChanges:
            Text("No Changes")
                .font(CursorType.rowSecondary)
                .foregroundColor(CursorPalette.mutedText)
        }
    }

    private var repoTag: some View {
        Text(model.repoName)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(CursorPalette.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(CursorPalette.composerBackground)
            )
    }
}

/// Floating stadium-shaped composer pinned above the safe area.
public struct CursorBottomComposer: View {
    @State private var text: String = ""

    public init() {}

    public var body: some View {
        HStack(spacing: 10) {
            TextField("Plan, ask, build...", text: $text)
                .font(CursorType.composerPlaceholder)
                .foregroundColor(CursorPalette.primaryText)
                .tint(CursorPalette.primaryText)

            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 26, weight: .regular))
                .foregroundColor(CursorPalette.primaryText)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .background(
            Capsule().fill(CursorPalette.composerBackground)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

/// Small muted section label, e.g. "Today" / "Yesterday".
public struct CursorSectionHeader: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(CursorType.sectionHeader)
            .foregroundColor(CursorPalette.secondaryText)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
