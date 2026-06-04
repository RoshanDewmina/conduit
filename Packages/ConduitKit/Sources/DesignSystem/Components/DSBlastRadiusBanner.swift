#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem

/// Inbox banner summarizing blast radius for an escalated approval.
public struct DSBlastRadiusBanner: View {
    let blastRadius: ApprovalBlastRadius

    @Environment(\.conduitTokens) private var t

    public init(blastRadius: ApprovalBlastRadius) {
        self.blastRadius = blastRadius
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "scope")
                    .font(.caption2)
                    .foregroundStyle(t.warn)
                Text("BLAST RADIUS")
                    .font(.dsDisplayPt(9, weight: .semibold))
                    .tracking(9 * 0.12)
                    .foregroundStyle(t.warn)
                Spacer()
                if let rule = blastRadius.matchedRule {
                    Text(rule)
                        .font(.dsMonoPt(10))
                        .foregroundStyle(t.text3)
                        .lineLimit(1)
                }
            }
            HStack(spacing: 8) {
                if blastRadius.touchesGit == true {
                    DSChip("git", tone: .warn, variant: .soft, size: .sm)
                }
                if blastRadius.touchesNetwork == true {
                    DSChip("network", tone: .danger, variant: .soft, size: .sm)
                }
            }
            if let files = blastRadius.files, !files.isEmpty {
                Text(files.prefix(5).joined(separator: " · "))
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text2)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(t.surfaceSunk)
        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                .strokeBorder(t.warn.opacity(0.35), lineWidth: 1)
        )
    }
}

#endif
