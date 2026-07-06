#if os(iOS)
import SwiftUI

/// A file row in Ship & History's file list — filename, muted path, and a
/// colored diffstat, with an expand chevron that reveals its diff inline.
private struct CursorPRFileModel: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let added: Int
    let removed: Int
}

/// Visual clone of Cursor's mobile PR detail / Ship & History screen
/// (IMG_2364-2367): header with back/link/menu actions, the PR title, a
/// status-pills row, an all-checks-passed card with a full-width "Mark Ready"
/// button, and a scrollable file list that expands one file's unified diff
/// inline. Static seed data only — no daemon/network wiring. Always light,
/// per the reference screenshots.
public struct CursorPRDetailView: View {
    @State private var expandedFileID: CursorPRFileModel.ID?
    @State private var showMenu = false

    public init() {}

    private let prTitle = "fix(relay): retry backoff on reconnect"
    private let prNumber = "#142"
    private let statusPill = "Open"
    private let infoPills = ["No Conflicts", "3 Commits"]

    private let files: [CursorPRFileModel] = [
        CursorPRFileModel(name: "RelayReconnectManager.swift", path: "Packages/LancerKit/Sources/SSHTransport", added: 54, removed: 12),
        CursorPRFileModel(name: "E2ERelayClient.swift", path: "Packages/LancerKit/Sources/AppFeature", added: 23, removed: 8),
        CursorPRFileModel(name: "ConnectionStateStore.swift", path: "Packages/LancerKit/Sources/AppFeature", added: 18, removed: 3),
        CursorPRFileModel(name: "RelayReconnectManagerTests.swift", path: "Packages/LancerKit/Tests/SSHTransportTests", added: 76, removed: 0),
        CursorPRFileModel(name: "dispatch.go", path: "daemon/lancerd", added: 9, removed: 2),
        CursorPRFileModel(name: "CHANGELOG.md", path: "docs", added: 4, removed: 0)
    ]

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            content
            if showMenu {
                menuPopover
                    .padding(.top, CursorMetrics.headerButtonDiameter + CursorMetrics.headerTopPadding + 6)
                    .padding(.trailing, CursorMetrics.headerHorizontalPadding)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
            }
        }
        .environment(\.cursorScheme, .light)
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    titleBlock
                    pillsRow
                    checksCard
                    CursorSectionHeader("\(files.count) Files")
                    fileList
                }
                .padding(.bottom, 24)
            }
        }
        .background(CursorColors.light.background.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture {
            if showMenu { showMenu = false }
        }
    }

    // MARK: Header

    private var header: some View {
        CursorHeaderBar(
            leading: AnyView(CursorIconButton(systemImageName: "chevron.left", action: {})),
            trailing: [
                CursorIconButton(systemImageName: "link", action: {}),
                CursorIconButton(systemImageName: "ellipsis", action: {
                    withAnimation(.easeInOut(duration: 0.15)) { showMenu.toggle() }
                })
            ]
        )
    }

    private var menuPopover: some View {
        VStack(spacing: 0) {
            Button(action: { showMenu = false }) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 20)
                    Text("Open in GitHub")
                        .font(CursorType.rowTitle)
                    Spacer(minLength: 0)
                }
                .foregroundColor(CursorColors.light.primaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(CursorColors.light.hairline)
                .frame(height: 1)

            Button(action: { showMenu = false }) {
                HStack(spacing: 10) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 20)
                    Text("Close PR")
                        .font(CursorType.rowTitle)
                    Spacer(minLength: 0)
                }
                .foregroundColor(CursorColors.light.dangerRed)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 220)
        .background(CursorColors.light.sheetBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(CursorColors.light.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
    }

    // MARK: Title + pills

    private var titleBlock: some View {
        (
            Text("\(prTitle) ")
                .font(CursorType.prTitle)
                .foregroundColor(CursorColors.light.primaryText)
            + Text(prNumber)
                .font(CursorType.prTitle)
                .foregroundColor(CursorColors.light.mutedText)
        )
        .padding(.horizontal, CursorMetrics.pageTitleLeadingPadding)
        .padding(.top, CursorMetrics.pageTitleTopPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pillsRow: some View {
        HStack(spacing: 10) {
            Text(statusPill)
                .font(CursorType.statusPill)
                .foregroundColor(CursorColors.light.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(CursorColors.light.composerBackground)
                .clipShape(Capsule())

            ForEach(Array(infoPills.enumerated()), id: \.offset) { index, label in
                if index > 0 {
                    Rectangle()
                        .fill(CursorColors.light.hairline)
                        .frame(width: 1, height: 14)
                }
                Text(label)
                    .font(CursorType.statusPill)
                    .foregroundColor(CursorColors.light.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CursorMetrics.pageTitleLeadingPadding)
        .padding(.top, 12)
    }

    // MARK: Checks card

    private var checksCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            CursorStatusBadge(kind: .success, label: "All Checks Passed")
                .padding(.horizontal, -CursorMetrics.statusBadgeHorizontalPadding)

            CursorPillButton(title: "Mark Ready", style: .secondary, fullWidth: true, action: {})
        }
        .padding(CursorMetrics.cardPadding)
        .background(CursorColors.light.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CursorMetrics.cardCornerRadius))
        .padding(.horizontal, CursorMetrics.pageTitleLeadingPadding)
        .padding(.top, 20)
    }

    // MARK: File list

    private var fileList: some View {
        VStack(spacing: 0) {
            ForEach(files) { file in
                fileRow(file)
            }
        }
    }

    private func fileRow(_ file: CursorPRFileModel) -> some View {
        let isExpanded = expandedFileID == file.id
        return VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedFileID = isExpanded ? nil : file.id
                }
            }) {
                HStack(spacing: CursorMetrics.rowSpacing) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(CursorColors.light.mutedText)
                        .frame(width: 14)

                    HStack(spacing: 6) {
                        Text(file.name)
                            .font(CursorType.rowTitle)
                            .foregroundColor(CursorColors.light.primaryText)
                            .lineLimit(1)
                        Text(file.path)
                            .font(CursorType.rowSecondary)
                            .foregroundColor(CursorColors.light.mutedText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 8)

                    CursorDiffStatText(added: file.added, removed: file.removed, font: CursorType.statusPill)
                }
                .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
                .padding(.vertical, CursorMetrics.rowVerticalPadding)
            }
            .buttonStyle(.plain)

            if isExpanded {
                CursorDiffView(collapsedContextLineCount: 48, lines: CursorDiffView.sampleRelayBackoffDiff)
                    .padding(.bottom, 12)
            }

            Rectangle()
                .fill(CursorColors.light.hairline)
                .frame(height: CursorMetrics.rowHairlineHeight)
                .padding(.leading, CursorMetrics.rowHorizontalPadding)
        }
    }
}
#endif
