#if os(iOS)
import SwiftUI
import LancerCore

public struct BlastRadiusView: View {
    let blastRadius: BlastRadius
    let reason: String?

    @Environment(\.lancerTokens) private var t

    public init(blastRadius: BlastRadius, reason: String? = nil) {
        self.blastRadius = blastRadius
        self.reason = reason
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: severity dot + label
            HStack(spacing: 6) {
                DSStatusDot(tone: severityDotTone, pulse: blastRadius.severity == .high)
                Text("BLAST RADIUS")
                    .font(.dsDisplayPt(9, weight: .semibold))
                    .tracking(9 * 0.12)
                    .foregroundStyle(severityColor)
                Spacer()
                Text(blastRadius.severity.rawValue.uppercased())
                    .font(.dsMonoPt(10))
                    .foregroundStyle(severityColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(severityColor.opacity(0.14), in: Capsule())
            }

            // Command(s)
            if !blastRadius.commands.isEmpty {
                Text(blastRadius.commands.joined(separator: " && "))
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text2)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            }

            // Reason
            if let reason, !reason.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 10))
                        .foregroundStyle(t.text4)
                    Text(reason)
                        .font(.dsSansPt(13))
                        .foregroundStyle(t.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Chips row
            chipRow
        }
        .padding(14)
        .background(t.surfaceSunk)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(severityColor.opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var chipRow: some View {
        if !blastRadius.affectedPaths.isEmpty || blastRadius.touchesProduction {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if blastRadius.touchesProduction {
                            DSChip(
                                "production",
                                systemImage: "exclamationmark.triangle.fill",
                                tone: .danger,
                                variant: .soft,
                                size: .sm
                            )
                        }
                        let count = blastRadius.affectedPathCount
                        if count > 0 {
                            DSChip(
                                "\(count) path\(count == 1 ? "" : "s")",
                                systemImage: "folder.fill",
                                tone: severityChipTone,
                                variant: .soft,
                                size: .sm
                            )
                        }
                        ForEach(blastRadius.affectedPaths.prefix(4), id: \.self) { path in
                            DSChip(path, tone: .neutral, variant: .mono, size: .sm)
                        }
                        if blastRadius.affectedPaths.count > 4 {
                            DSChip("+\(blastRadius.affectedPaths.count - 4) more", tone: .neutral, variant: .solid, size: .sm)
                        }
                    }
                }
            }
        }
    }

    private var severityColor: Color {
        switch blastRadius.severity {
        case .low:    return t.ok
        case .medium: return t.warn
        case .high:   return t.danger
        }
    }

    private var severityDotTone: DSStatusDotTone {
        switch blastRadius.severity {
        case .low:    return .ok
        case .medium: return .warn
        case .high:   return .danger
        }
    }

    private var severityChipTone: DSChipTone {
        switch blastRadius.severity {
        case .low:    return .ok
        case .medium: return .warn
        case .high:   return .danger
        }
    }
}

#Preview {
    let br = BlastRadius.derive(
        fromCommand: "rm -rf build/ && npm run deploy",
        cwd: "."
    )
    return BlastRadiusView(
        blastRadius: br,
        reason: "Clean rebuild before shipping."
    )
    .padding()
    .background(Color(.systemBackground))
}

#endif
