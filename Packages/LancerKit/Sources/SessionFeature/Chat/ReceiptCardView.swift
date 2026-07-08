#if os(iOS)
import SwiftUI
import LancerCore
import DesignSystem

/// Proof receipt card for a completed agent run (`lancer.proof/v0`).
/// A3-R4 Cursor-language pass: draws exclusively from `CursorColors`/
/// `CursorType`/`CursorPillButton` (this card is only ever hosted by the
/// Cursor-style `CursorWorkThreadView`).
public struct ReceiptCardView: View {
    let artifact: ChatArtifact
    let receipt: ProofReceipt
    let workingDirectory: String?
    let onAccept: () -> Void
    let onRequestAnotherPass: (String) -> Void
    let onOpenOnDesktop: (String) -> Void

    @State private var filesExpanded = false
    @State private var commandsExpanded = false
    @State private var showingProofReel = false
    @Environment(\.cursorScheme) private var cursorScheme

    private var colors: CursorColors { CursorColors.resolve(cursorScheme) }

    private var accepted: Bool { ReceiptCardModel.isAccepted(payloadJSON: artifact.payloadJSON) }

    public init(
        artifact: ChatArtifact,
        receipt: ProofReceipt,
        workingDirectory: String? = nil,
        onAccept: @escaping () -> Void,
        onRequestAnotherPass: @escaping (String) -> Void,
        onOpenOnDesktop: @escaping (String) -> Void
    ) {
        self.artifact = artifact
        self.receipt = receipt
        self.workingDirectory = workingDirectory
        self.onAccept = onAccept
        self.onRequestAnotherPass = onRequestAnotherPass
        self.onOpenOnDesktop = onOpenOnDesktop
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(gutterColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)

                if let goal = receipt.contract?.goal, !goal.isEmpty {
                    goalSection(goal)
                }

                if !criteriaRows.isEmpty {
                    sectionDivider
                    criteriaSection
                }

                if testsSummary != nil {
                    sectionDivider
                    testsSection
                }

                if !fileRows.isEmpty {
                    sectionDivider
                    filesSection
                }

                if !commandRows.isEmpty {
                    sectionDivider
                    commandsSection
                }

                if hasConfidenceCaptions {
                    sectionDivider
                    confidenceSection
                }

                sectionDivider
                actionsSection
            }
        }
        .background(colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CursorMetrics.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CursorMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(colors.hairline, lineWidth: 0.75)
        )
        // .contain keeps the card itself in the accessibility tree as a
        // container element; without it SwiftUI smears the identifier onto
        // every child StaticText and otherElements["receipt-card"] matches
        // nothing (found via the failing exhaustive test's hierarchy dump).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("receipt-card")
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .sheet(isPresented: $showingProofReel) {
            ProofReelView(receipt: receipt)
        }
        #if DEBUG
        .onAppear { applyDebugProofReelSeamIfNeeded() }
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Proof")
                        .foregroundStyle(colors.secondaryText)
                        .fontWeight(.semibold)
                    Text("›")
                        .foregroundStyle(colors.mutedText)
                    Text(receipt.agent)
                        .foregroundStyle(colors.mutedText)
                }
                .font(.dsMonoPt(10))
                .tracking(10 * 0.12)
                .textCase(.uppercase)
                .lineLimit(1)

                if let duration = ReceiptCardModel.durationText(
                    startedAt: receipt.startedAt,
                    endedAt: receipt.endedAt
                ) {
                    Text(duration)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(colors.mutedText)
                }
            }

            Spacer(minLength: 8)

            statusBadge
            if let code = receipt.exitCode {
                DSExitChip(code: code)
            }
            if accepted {
                acceptedBadge
            }
        }
    }

    private var statusBadge: some View {
        Text(receipt.status.replacingOccurrences(of: "_", with: " "))
            .font(.dsMonoPt(10, weight: .semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.12))
            .clipShape(Capsule())
    }

    private var acceptedBadge: some View {
        HStack(spacing: 4) {
            DSIconView(.check, size: 11, color: colors.successGreen)
            Text("Accepted")
                .font(.dsMonoPt(10, weight: .semibold))
        }
        .foregroundStyle(colors.successGreen)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(colors.successGreen.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityIdentifier("receipt-accepted-badge")
    }

    // MARK: - Sections

    private func goalSection(_ goal: String) -> some View {
        sectionBlock(label: "Goal") {
            Text(goal)
                .font(.dsMonoPt(12))
                .foregroundStyle(colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var criteriaSection: some View {
        sectionBlock(label: "Done criteria") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(criteriaRows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 8) {
                        criterionIcon(for: row.status)
                            .frame(width: 14, height: 14)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.text)
                                .font(.dsMonoPt(12))
                                .foregroundStyle(colors.primaryText)
                            if let evidence = row.evidence, !evidence.isEmpty {
                                Text(evidence)
                                    .font(.dsMonoPt(10))
                                    .foregroundStyle(colors.mutedText)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("receipt-criteria")
    }

    private var testsSection: some View {
        sectionBlock(label: "Tests") {
            HStack {
                Text(testsSummary ?? "")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(colors.primaryText)
                Spacer(minLength: 0)
                if let caption = ReceiptCardModel.confidenceCaption(receipt.confidence?.tests) {
                    Text(caption)
                        .font(.dsMonoPt(10))
                        .foregroundStyle(colors.mutedText)
                }
            }
        }
        .accessibilityIdentifier("receipt-tests")
    }

    private var filesSection: some View {
        let visible = filesExpanded ? fileRows : Array(fileRows.prefix(5))
        return sectionBlock(label: "Files touched") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, file in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(shortPath(file.path))
                            .font(.dsMonoPt(11))
                            .foregroundStyle(colors.primaryText)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("+\(file.additions) -\(file.deletions)")
                            .font(.dsMonoPt(10))
                            .foregroundStyle(colors.mutedText)
                    }
                }
                if fileRows.count > 5 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { filesExpanded.toggle() }
                    } label: {
                        Text(filesExpanded ? "Show fewer" : "Show \(fileRows.count - 5) more")
                            .font(.dsMonoPt(10, weight: .semibold))
                            .foregroundStyle(colors.orangeAccent)
                    }
                    .buttonStyle(.plain)
                }
                if let caption = ReceiptCardModel.confidenceCaption(receipt.confidence?.files) {
                    Text(caption)
                        .font(.dsMonoPt(10))
                        .foregroundStyle(colors.mutedText)
                }
            }
        }
        .accessibilityIdentifier("receipt-files")
    }

    private var commandsSection: some View {
        sectionBlock(label: "Commands") {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { commandsExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: commandsExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(colors.mutedText)
                        Text("\(commandRows.count) command\(commandRows.count == 1 ? "" : "s")")
                            .font(.dsMonoPt(11, weight: .semibold))
                            .foregroundStyle(colors.secondaryText)
                        Spacer(minLength: 0)
                        if let caption = ReceiptCardModel.confidenceCaption(receipt.confidence?.commands) {
                            Text(caption)
                                .font(.dsMonoPt(10))
                                .foregroundStyle(colors.mutedText)
                        }
                    }
                }
                .buttonStyle(.plain)

                if commandsExpanded {
                    ForEach(Array(commandRows.enumerated()), id: \.offset) { _, command in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(command.command)
                                .font(.dsMonoPt(11))
                                .foregroundStyle(colors.primaryText)
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                            if let code = command.exitCode {
                                Text("exit \(code)")
                                    .font(.dsMonoPt(10))
                                    .foregroundStyle(code == 0 ? colors.successGreen : colors.dangerRed)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("receipt-commands")
    }

    private var confidenceSection: some View {
        sectionBlock(label: "Capture confidence") {
            VStack(alignment: .leading, spacing: 4) {
                confidenceRow("Commands", receipt.confidence?.commands)
                confidenceRow("Files", receipt.confidence?.files)
                confidenceRow("Tests", receipt.confidence?.tests)
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 8) {
            actionButton(
                title: accepted ? "Accepted" : "Accept",
                primary: true,
                disabled: accepted,
                identifier: "receipt-accept"
            ) {
                onAccept()
            }
            actionButton(
                title: "Request another pass",
                primary: false,
                disabled: false,
                identifier: "receipt-another-pass"
            ) {
                onRequestAnotherPass(ReceiptCardModel.anotherPassPrefill(receipt: receipt))
            }
            actionButton(
                title: "Open on desktop",
                primary: false,
                disabled: resumeCommand == nil,
                identifier: "receipt-open-desktop"
            ) {
                if let resumeCommand { onOpenOnDesktop(resumeCommand) }
            }
            actionButton(
                title: "Proof Reel",
                primary: false,
                disabled: ProofReelModel.stops(from: receipt).isEmpty,
                identifier: "receipt-proof-reel"
            ) {
                showingProofReel = true
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    #if DEBUG
    private func applyDebugProofReelSeamIfNeeded() {
        guard ProcessInfo.processInfo.environment["LANCER_PROOF_REEL_AUTO_PRESENT"] == "1" else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            showingProofReel = true
        }
    }
    #endif

    // MARK: - Building blocks

    private func sectionBlock<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.dsMonoPt(10))
                .tracking(10 * 0.12)
                .foregroundStyle(colors.mutedText)
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var sectionDivider: some View {
        Rectangle().fill(colors.hairline).frame(height: 1)
    }

    private func actionButton(
        title: String,
        primary: Bool,
        disabled: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.dsMonoPt(12, weight: .semibold))
                .foregroundStyle(primary ? colors.pillPrimaryText : colors.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(primary ? colors.orangeAccent : colors.composerBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    if !primary {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(colors.hairline, lineWidth: 0.75)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
        .accessibilityIdentifier(identifier)
    }

    private func criterionIcon(for status: ProofReceipt.Criterion.Status) -> some View {
        Group {
            switch status {
            case .met:
                DSIconView(.check, size: 12, color: colors.successGreen)
            case .unmet:
                DSIconView(.close, size: 12, color: colors.dangerRed)
            case .unknown:
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.mutedText)
            }
        }
    }

    @ViewBuilder
    private func confidenceRow(_ label: String, _ value: String?) -> some View {
        if let caption = ReceiptCardModel.confidenceCaption(value) {
            HStack {
                Text(label)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(colors.secondaryText)
                Spacer(minLength: 0)
                Text(caption)
                    .font(.dsMonoPt(10))
                    .foregroundStyle(colors.mutedText)
            }
        }
    }

    private func shortPath(_ path: String) -> String {
        if path.count <= 48 { return path }
        return "…" + path.suffix(45)
    }

    // MARK: - Derived

    private var criteriaRows: [ReceiptCardModel.CriterionRow] {
        ReceiptCardModel.criteriaRows(receipt: receipt)
    }

    private var fileRows: [ReceiptCardModel.FileRow] {
        ReceiptCardModel.fileRows(receipt: receipt)
    }

    private var commandRows: [ReceiptCardModel.CommandRow] {
        ReceiptCardModel.commandRows(receipt: receipt)
    }

    private var testsSummary: String? {
        ReceiptCardModel.testsSummaryText(receipt.tests)
    }

    private var resumeCommand: String? {
        ReceiptCardModel.resumeShellCommand(receipt: receipt, workingDirectory: workingDirectory)
    }

    private var hasConfidenceCaptions: Bool {
        receipt.confidence?.commands != nil
            || receipt.confidence?.files != nil
            || receipt.confidence?.tests != nil
    }

    private var gutterColor: Color {
        if accepted { return colors.successGreen.opacity(0.55) }
        if receipt.exitCode == 0 || receipt.status == "completed" { return colors.successGreen.opacity(0.55) }
        if receipt.exitCode != nil && receipt.exitCode != 0 { return colors.dangerRed }
        return colors.orangeAccent
    }

    private var statusColor: Color {
        switch receipt.status {
        case "completed": return colors.successGreen
        case "failed": return colors.dangerRed
        default: return colors.secondaryText
        }
    }
}
#endif
