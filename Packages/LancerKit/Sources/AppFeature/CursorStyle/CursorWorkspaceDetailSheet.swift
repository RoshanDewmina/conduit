#if os(iOS)
import SwiftUI
import DesignSystem

/// Sheet shown when the user taps a repo row in the Workspaces list.
/// Displays the repo name as the title and lists each RunTarget (machine
/// that has a checkout of this repo) with a connection-status indicator.
/// Status dot is derived from the bridge's `connectionPhase`; per-machine
/// phase is not available in T1 — Phase 2 can refine this per target.
public struct CursorWorkspaceDetailSheet: View {
    @Environment(\.cursorScheme) private var cursorScheme
    @Environment(\.cursorShellLiveBridge) private var liveBridge

    private let workspace: CursorShellLiveBridge.WorkspaceRow
    private let onClose: () -> Void

    public init(
        workspace: CursorShellLiveBridge.WorkspaceRow,
        onClose: @escaping () -> Void = {}
    ) {
        self.workspace = workspace
        self.onClose = onClose
    }

    public var body: some View {
        CursorBottomSheetContainer(
            title: workspace.name,
            leadingButton: (systemImageName: "xmark", action: onClose)
        ) {
            VStack(spacing: 0) {
                CursorSectionHeader("Run targets")
                if workspace.runTargets.isEmpty {
                    emptyState
                } else {
                    ForEach(workspace.runTargets) { target in
                        runTargetRow(target)
                    }
                }
            }
            .padding(.bottom, CursorMetrics.sheetContentBottomPadding)
        }
    }

    @ViewBuilder
    private func runTargetRow(_ target: CursorShellLiveBridge.RunTarget) -> some View {
        let colors = CursorColors.resolve(cursorScheme)
        let isOnline = liveBridge?.connectionPhase == .connected
        VStack(spacing: 0) {
            HStack(spacing: CursorMetrics.rowSpacing) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: CursorMetrics.rowIconSize - 6, weight: .regular))
                    .foregroundColor(colors.secondaryText)
                    .frame(width: CursorMetrics.rowIconSize, height: CursorMetrics.rowIconSize)
                Text(target.hostName)
                    .font(CursorType.rowTitle)
                    .foregroundColor(colors.primaryText)
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(isOnline ? colors.statusDotActive : colors.statusDotIdle)
                        .frame(
                            width: CursorMetrics.threadRowStatusDotSize,
                            height: CursorMetrics.threadRowStatusDotSize
                        )
                    Text(isOnline ? "online" : "offline")
                        .font(CursorType.rowSecondary)
                        .foregroundColor(colors.secondaryText)
                }
            }
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
            .padding(.vertical, CursorMetrics.rowVerticalPadding)
            Rectangle()
                .fill(colors.hairline)
                .frame(height: CursorMetrics.rowHairlineHeight)
                .padding(.leading, CursorMetrics.rowHairlineLeadingInsetWithIcon)
        }
        .accessibilityIdentifier("workspace-detail-target-row")
    }

    private var emptyState: some View {
        let colors = CursorColors.resolve(cursorScheme)
        return Text("No run targets found")
            .font(CursorType.rowSecondary)
            .foregroundColor(colors.secondaryText)
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
            .padding(.vertical, CursorMetrics.rowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
