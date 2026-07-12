#if os(iOS)
import SwiftUI
import LancerCore

/// Quiet run-proof summary for a completed agent turn (`lancer.proof/v0`).
/// Workspaces-shell chrome: system fills + outline pills (Cursor reference),
/// not the retired DesignSystem / CursorStyle token set.
///
/// Copy describes what was **observed** / **asked** of the agent — never
/// "guaranteed" (enforcement is a separate, later feature).
public struct ReceiptCardView: View {
    let receipt: ProofReceipt

    @State private var showingProofReel = false

    public init(receipt: ProofReceipt) {
        self.receipt = receipt
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            metaRows
            Button {
                showingProofReel = true
            } label: {
                ChatOutlinePillLabel(title: "Proof Reel", systemImage: "film")
            }
            .buttonStyle(.plain)
            .disabled(!canOpenProofReel)
            .opacity(canOpenProofReel ? 1 : 0.45)
            .accessibilityIdentifier("receipt-proof-reel")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("receipt-card")
        .sheet(isPresented: $showingProofReel) {
            ProofReelView(receipt: receipt)
        }
        #if DEBUG
        .onAppear { applyDebugProofReelSeamIfNeeded() }
        #endif
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Proof")
                .font(.system(size: 15, weight: .semibold))
            Text("observed")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(receipt.status.replacingOccurrences(of: "_", with: " "))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    private var metaRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            metaLine(label: "Agent", value: agentLine)
            if let duration = ProofReelModel.durationText(
                startedAt: receipt.startedAt,
                endedAt: receipt.endedAt
            ) {
                metaLine(label: "Duration", value: duration)
            }
            if let gitLine {
                metaLine(label: "Git", value: gitLine)
            }
            metaLine(label: "Files", value: filesLine)
            if let goal = receipt.contract?.goal, !goal.isEmpty {
                metaLine(label: "Asked", value: goal)
            }
        }
    }

    private func metaLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 13, design: label == "Git" || label == "Agent" ? .monospaced : .default))
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
    }

    private var agentLine: String {
        if let model = receipt.model, !model.isEmpty {
            return "\(receipt.agent) · \(model)"
        }
        return receipt.agent
    }

    private var gitLine: String? {
        let start = ProofReelModel.shortGitRef(receipt.git?.startRef)
        let end = ProofReelModel.shortGitRef(receipt.git?.endRef)
        guard start != nil || end != nil || receipt.git?.dirtyAtStart != nil else { return nil }
        var parts: [String] = []
        switch (start, end) {
        case let (s?, e?):
            parts.append("\(s) → \(e)")
        case let (s?, nil):
            parts.append(s)
        case let (nil, e?):
            parts.append(e)
        case (nil, nil):
            break
        }
        if receipt.git?.dirtyAtStart == true {
            parts.append("dirty at start")
        } else if receipt.git?.dirtyAtStart == false {
            parts.append("clean at start")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var filesLine: String {
        let count = receipt.filesTouched?.count ?? 0
        if count == 0 { return "0 touched (observed)" }
        return "\(count) touched (observed)"
    }

    private var canOpenProofReel: Bool {
        !ProofReelModel.stops(from: receipt).isEmpty
    }

    private var statusColor: Color {
        switch receipt.status {
        case "completed": return .green
        case "failed": return .red
        default: return .secondary
        }
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
}

/// One-line collapsed proof chip — the full card expands on tap. Replaces the
/// full-height Proof card inline in transcripts (owner decision 2026-07-12:
/// receipts read as a chip; detail on demand).
public struct ReceiptChipRow: View {
    let receipt: ProofReceipt

    @State private var isExpanded = false

    public init(receipt: ProofReceipt) {
        self.receipt = receipt
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(chipTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Proof: \(chipTitle)"))
            .accessibilityHint(Text(isExpanded ? "Collapse proof" : "Expand proof"))

            if isExpanded {
                ReceiptCardView(receipt: receipt)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chipTitle: String {
        var parts = ["Proof", receipt.status]
        if let duration = ProofReelModel.durationText(
            startedAt: receipt.startedAt, endedAt: receipt.endedAt
        ) {
            parts.append(duration)
        }
        return parts.joined(separator: " · ")
    }
}

#endif
