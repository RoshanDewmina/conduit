#if os(iOS)
import SwiftUI
import DesignSystem
import LancerCore

public struct ChatArtifactCard: View {
    let artifact: ChatArtifact
    let onTap: (() -> Void)?

    public init(artifact: ChatArtifact, onTap: (() -> Void)? = nil) {
        self.artifact = artifact
        self.onTap = onTap
    }

    public var body: some View {
        Button { onTap?() } label: {
            cardBody
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }

    @ViewBuilder
    private var cardBody: some View {
        switch artifact.kind {
        case .tool:
            ChatToolArtifactCard(artifact: artifact)
        case .diff:
            ChatDiffArtifactCard(artifact: artifact)
        case .file:
            ChatFileArtifactCard(artifact: artifact)
        case .test:
            ChatTestArtifactCard(artifact: artifact)
        case .preview:
            ChatPreviewArtifactCard(artifact: artifact)
        case .approval:
            ChatApprovalArtifactCard(artifact: artifact)
        }
    }
}

private struct ChatToolArtifactCard: View {
    let artifact: ChatArtifact
    @Environment(\.lancerTokens) private var t

    private var toolSummary: String {
        guard let data = artifact.payloadJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return artifact.summary ?? artifact.title }
        if let cmd = json["command"] as? String { return cmd }
        if let path = json["path"] as? String { return path }
        return artifact.summary ?? artifact.title
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(barColor)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(artifact.title.uppercased())
                        .font(.dsMonoPt(9, weight: .semibold))
                        .foregroundStyle(t.text4)
                        .tracking(0.8)
                    Spacer()
                    statusIndicator
                }
                Text(toolSummary)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(t.surfaceSunk)
        .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
    }

    private var barColor: Color {
        artifact.status == .running ? t.accent : t.ok
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if artifact.status == .running {
            PixelBox(state: .streaming, size: 7, subdivisions: 2)
        } else {
            DSStatusDot(tone: artifact.status == .done ? .ok : .danger, size: 6)
        }
    }
}

private struct ChatDiffArtifactCard: View {
    let artifact: ChatArtifact
    @Environment(\.lancerTokens) private var t

    private var diffStats: (insertions: Int, deletions: Int)? {
        guard let data = artifact.payloadJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let ins = json["insertions"] as? Int ?? json["plus"] as? Int
        let del = json["deletions"] as? Int ?? json["minus"] as? Int
        guard let i = ins, let d = del else { return nil }
        return (i, d)
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(t.accent)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("DIFF")
                        .font(.dsMonoPt(9, weight: .semibold))
                        .foregroundStyle(t.text4)
                        .tracking(0.8)
                    Spacer()
                    if let stats = diffStats {
                        HStack(spacing: 4) {
                            Text("+\(stats.insertions)")
                                .font(.dsMonoPt(10))
                                .foregroundStyle(t.ok)
                            Text("-\(stats.deletions)")
                                .font(.dsMonoPt(10))
                                .foregroundStyle(t.danger)
                        }
                    }
                    statusIndicator
                }
                Text(artifact.summary ?? artifact.title)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text)
                    .lineLimit(2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(t.surfaceSunk)
        .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if artifact.status == .running {
            PixelBox(state: .streaming, size: 7, subdivisions: 2)
        } else {
            DSStatusDot(tone: artifact.status == .done ? .ok : .danger, size: 6)
        }
    }
}

private struct ChatFileArtifactCard: View {
    let artifact: ChatArtifact
    @Environment(\.lancerTokens) private var t

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(t.ok)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("FILE")
                        .font(.dsMonoPt(9, weight: .semibold))
                        .foregroundStyle(t.text4)
                        .tracking(0.8)
                    Spacer()
                    DSStatusDot(tone: artifact.status == .done ? .ok : artifact.status == .running ? .accent : .danger, size: 6)
                }
                Text(artifact.title)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text)
                    .lineLimit(2)
                if let summary = artifact.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(t.surfaceSunk)
        .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
    }
}

private struct ChatTestArtifactCard: View {
    let artifact: ChatArtifact
    @Environment(\.lancerTokens) private var t

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(artifact.status == .done ? t.ok : artifact.status == .failed ? t.danger : t.accent)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("TEST")
                        .font(.dsMonoPt(9, weight: .semibold))
                        .foregroundStyle(t.text4)
                        .tracking(0.8)
                    Spacer()
                    statusChip
                }
                Text(artifact.summary ?? artifact.title)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text)
                    .lineLimit(3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(t.surfaceSunk)
        .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
    }

    @ViewBuilder
    private var statusChip: some View {
        if artifact.status == .running {
            PixelBox(state: .streaming, size: 7, subdivisions: 2)
        } else {
            let passed = artifact.status == .done
            HStack(spacing: 3) {
                DSIconView(passed ? .check : .close, size: 10, color: passed ? t.ok : t.danger)
                Text(passed ? "PASS" : "FAIL")
                    .font(.dsMonoPt(9, weight: .semibold))
                    .foregroundStyle(passed ? t.ok : t.danger)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(passed ? t.okSoft : t.dangerSoft)
            .clipShape(Capsule())
        }
    }
}

private struct ChatPreviewArtifactCard: View {
    let artifact: ChatArtifact
    @Environment(\.lancerTokens) private var t

    private var previewURL: String? {
        if let data = artifact.payloadJSON.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let url = json["url"] as? String {
            return url
        }
        return artifact.summary ?? artifact.title
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(t.accent)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("PREVIEW")
                        .font(.dsMonoPt(9, weight: .semibold))
                        .foregroundStyle(t.text4)
                        .tracking(0.8)
                    Spacer()
                    DSStatusDot(tone: .accent, size: 6)
                }
                if let url = previewURL {
                    Text(url)
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.accent)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(t.surfaceSunk)
        .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
    }
}

private struct ChatApprovalArtifactCard: View {
    let artifact: ChatArtifact
    @Environment(\.lancerTokens) private var t

    private var approvalStatus: ApprovalStatus {
        switch artifact.status {
        case .running: return .pending
        case .done:    return .approved
        case .failed:  return .denied
        }
    }

    private enum ApprovalStatus { case pending, approved, denied }

    private var statusLabel: String {
        switch approvalStatus {
        case .pending:  return "PENDING"
        case .approved: return "APPROVED"
        case .denied:   return "DENIED"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(barColor)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("APPROVAL")
                        .font(.dsMonoPt(9, weight: .semibold))
                        .foregroundStyle(t.text4)
                        .tracking(0.8)
                    Spacer()
                    Text(statusLabel)
                        .font(.dsMonoPt(9, weight: .semibold))
                        .foregroundStyle(chipFg)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(chipBg)
                        .clipShape(Capsule())
                }
                if artifact.summary == nil && artifact.payloadJSON == "{}" {
                    Text("Open in Inbox")
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text3)
                        .italic()
                } else {
                    Text(artifact.summary ?? artifact.title)
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text)
                        .lineLimit(3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(t.surfaceSunk)
        .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
    }

    private var barColor: Color {
        switch approvalStatus {
        case .pending:  return t.warn
        case .approved: return t.ok
        case .denied:   return t.danger
        }
    }

    private var chipBg: Color {
        switch approvalStatus {
        case .pending:  return t.warnSoft
        case .approved: return t.okSoft
        case .denied:   return t.dangerSoft
        }
    }

    private var chipFg: Color {
        switch approvalStatus {
        case .pending:  return t.warn
        case .approved: return t.ok
        case .denied:   return t.danger
        }
    }
}

#endif
