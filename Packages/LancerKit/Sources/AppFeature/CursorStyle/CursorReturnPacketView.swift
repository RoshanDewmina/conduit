#if os(iOS)
import SwiftUI
import DesignSystem
import LancerCore
import SessionFeature

/// Return-to-Desk packet: composes receipt contract, open risks, git/worktree
/// state, and a copyable desktop continuation command so the owner can pick up
/// on the computer where the phone left off. Read-only — nothing executes here.
public struct CursorReturnPacketView: View {
    let receipt: ProofReceipt
    let workingDirectory: String?
    let onDismiss: () -> Void

    @Environment(\.lancerTokens) private var t
    @State private var copied = false

    public init(
        receipt: ProofReceipt,
        workingDirectory: String? = nil,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.receipt = receipt
        self.workingDirectory = workingDirectory
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let goal = receipt.contract?.goal, !goal.isEmpty {
                        goalSection(goal)
                    }

                    if !unmetRows.isEmpty {
                        risksSection
                    }

                    if hasGitSection {
                        gitSection
                    }

                    if let command = continuationCommand {
                        commandSection(command)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        }
        .background(CursorColors.light.background.ignoresSafeArea())
        .environment(\.cursorScheme, .light)
        .lancerTokens(appearance: .light)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("return-packet-screen")
    }

    // MARK: Header

    private var header: some View {
        CursorHeaderBar(
            leading: AnyView(
                CursorIconButton(systemImageName: "chevron.left", action: onDismiss)
            ),
            trailing: []
        )
        .overlay(alignment: .center) {
            Text("Continue on desktop")
                .font(CursorType.sheetTitle)
                .foregroundColor(CursorColors.light.primaryText)
                .padding(.top, CursorMetrics.headerTopPadding)
        }
    }

    // MARK: Sections

    private func goalSection(_ goal: String) -> some View {
        packetCard(title: "Goal") {
            Text(goal)
                .font(CursorType.bodyText)
                .foregroundStyle(t.termText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("return-packet-goal")
        }
    }

    private var risksSection: some View {
        packetCard(title: "Open items") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(unmetRows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 8) {
                        DSIconView(.close, size: 12, color: t.termErr)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.text)
                                .font(.dsMonoPt(12))
                                .foregroundStyle(t.termText)
                            if let evidence = row.evidence, !evidence.isEmpty {
                                Text(evidence)
                                    .font(.dsMonoPt(10))
                                    .foregroundStyle(t.termText3)
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("return-packet-risks")
        }
    }

    private var gitSection: some View {
        packetCard(title: "Git state") {
            VStack(alignment: .leading, spacing: 8) {
                if let branch = gitBranchLabel {
                    labeledRow("Branch", branch, identifier: "return-packet-branch")
                }
                if let path = worktreePath {
                    labeledRow("Worktree", path, identifier: "return-packet-worktree")
                }
                if let dirty = dirtyAtStart {
                    labeledRow(
                        "Dirty at start",
                        dirty ? "Yes — uncommitted changes present" : "No",
                        identifier: "return-packet-dirty"
                    )
                }
            }
        }
    }

    private func commandSection(_ command: String) -> some View {
        packetCard(title: "Continue on desktop") {
            VStack(alignment: .leading, spacing: 12) {
                Text(command)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.termText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(t.termSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: t.radiusSM, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: t.radiusSM, style: .continuous)
                            .strokeBorder(t.termBorder, lineWidth: 0.75)
                    )
                    .accessibilityIdentifier("return-packet-command")

                Button {
                    UIPasteboard.general.string = command
                    copied = true
                } label: {
                    Text(copied ? "Copied" : "Copy command")
                        .font(.dsMonoPt(12, weight: .semibold))
                        .foregroundStyle(t.accentFg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(t.termAccent)
                        .clipShape(RoundedRectangle(cornerRadius: t.radiusSM, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("return-packet-copy")
            }
        }
    }

    // MARK: Building blocks

    private func packetCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.dsMonoPt(10))
                .tracking(10 * 0.12)
                .foregroundStyle(t.termText3)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.termSurface)
        .clipShape(RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous)
                .strokeBorder(t.termBorder, lineWidth: 0.75)
        )
    }

    private func labeledRow(_ label: String, _ value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.dsMonoPt(10))
                .foregroundStyle(t.termText3)
            Text(value)
                .font(.dsMonoPt(12))
                .foregroundStyle(t.termText)
                .textSelection(.enabled)
        }
        .accessibilityIdentifier(identifier)
    }

    // MARK: Derived

    private var unmetRows: [ReceiptCardModel.CriterionRow] {
        ReturnPacketModel.unmetCriteria(receipt: receipt)
    }

    private var gitBranchLabel: String? {
        ReturnPacketModel.gitBranchLabel(receipt: receipt)
    }

    private var worktreePath: String? {
        ReturnPacketModel.worktreePath(receipt: receipt, workingDirectory: workingDirectory)
    }

    private var dirtyAtStart: Bool? {
        ReturnPacketModel.dirtyAtStart(receipt: receipt)
    }

    private var continuationCommand: String? {
        ReturnPacketModel.continuationCommand(receipt: receipt, workingDirectory: workingDirectory)
    }

    private var hasGitSection: Bool {
        gitBranchLabel != nil || worktreePath != nil || dirtyAtStart != nil
    }
}
#endif
