#if os(iOS)
import SwiftUI
import DesignSystem
import ConduitCore

public struct ChatArtifactDetailView: View {
    let artifact: ChatArtifact
    let onDecision: ((Bool) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    public init(artifact: ChatArtifact, onDecision: ((Bool) -> Void)? = nil) {
        self.artifact = artifact
        self.onDecision = onDecision
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                t.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerSection
                        Divider().background(t.border)
                        contentSection
                    }
                    .padding(16)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.dsSansPt(14, weight: .medium))
                        .foregroundStyle(t.accent)
                }
            }
        }
    }

    private var title: String {
        switch artifact.kind {
        case .tool:    return "Tool Call"
        case .diff:    return "Diff"
        case .file:    return "File"
        case .test:    return "Test"
        case .preview: return "Preview"
        case .approval: return "Approval"
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                kindBadge
                statusBadge
                Spacer()
            }
            Text(artifact.title)
                .font(.dsDisplayPt(18, weight: .bold))
                .foregroundStyle(t.text)
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        switch artifact.kind {
        case .tool:
            toolDetail
        case .diff:
            diffDetail
        case .file:
            fileDetail
        case .test:
            testDetail
        case .preview:
            previewDetail
        case .approval:
            approvalDetail
        }
    }

    // MARK: - Kind badge

    @ViewBuilder
    private var kindBadge: some View {
        let pair = kindBadgePair
        HStack(spacing: 4) {
            DSIconView(pair.icon, size: 12, color: t.accent)
            Text(pair.label)
                .font(.dsMonoPt(10, weight: .semibold))
                .tracking(1.0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(t.accentSoft)
        .foregroundStyle(t.accent)
        .clipShape(Capsule())
    }

    private var kindBadgePair: (label: String, icon: DSIcon) {
        switch artifact.kind {
        case .tool:    return ("TOOL", .terminal)
        case .diff:    return ("DIFF", .diff)
        case .file:    return ("FILE", .file)
        case .test:    return ("TEST", .check)
        case .preview: return ("PREVIEW", .globe)
        case .approval: return ("APPROVAL", .shield)
        }
    }

    // MARK: - Status badge

    @ViewBuilder
    private var statusBadge: some View {
        let triple = statusBadgeTriple
        Text(triple.label)
            .font(.dsMonoPt(10, weight: .semibold))
            .tracking(1.0)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(triple.bg)
            .foregroundStyle(triple.fg)
            .clipShape(Capsule())
    }

    private var statusBadgeTriple: (label: String, bg: Color, fg: Color) {
        switch artifact.status {
        case .running: return ("RUNNING", t.accentSoft, t.accent)
        case .done:    return ("DONE", t.okSoft, t.ok)
        case .failed:  return ("FAILED", t.dangerSoft, t.danger)
        }
    }

    // MARK: - Tool detail

    private var toolDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(formattedJSON)
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .background(t.surfaceSunk)
                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1)
                )
            } label: {
                Text("Payload")
                    .font(.dsMonoPt(12, weight: .medium))
                    .foregroundStyle(t.text2)
            }
        }
    }

    // MARK: - Diff detail

    private var diffDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary = artifact.summary {
                Text(summary)
                    .font(.dsSansPt(14))
                    .foregroundStyle(t.text2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(diffText)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(t.surfaceSunk)
            .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
        }
    }

    private var diffText: String {
        if let data = artifact.payloadJSON.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let diff = json["diff"] as? String {
            return diff
        }
        return artifact.summary ?? "(no diff content)"
    }

    // MARK: - File detail

    private var fileDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                DSIconView(.file, size: 16, color: t.ok)
                Text(artifact.title)
                    .font(.dsMonoPt(13))
                    .foregroundStyle(t.text)
                    .textSelection(.enabled)
            }
            if let summary = artifact.summary, !summary.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(summary)
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .background(t.surfaceSunk)
                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Test detail

    private var testDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary = artifact.summary {
                Text(summary)
                    .font(.dsSansPt(14))
                    .foregroundStyle(t.text2)
            }
            if let data = artifact.payloadJSON.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let output = json["output"] as? String, !output.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(output)
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .background(t.surfaceSunk)
                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Preview detail

    private var previewDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            let url = previewURL
            HStack(spacing: 8) {
                DSIconView(.globe, size: 16, color: t.accent)
                Text(url)
                    .font(.dsMonoPt(13))
                    .foregroundStyle(t.accent)
                    .textSelection(.enabled)
            }
            if let urlObj = URL(string: url) {
                Link(destination: urlObj) {
                    HStack(spacing: 6) {
                        DSIconView(.link, size: 14, color: t.accentFg)
                        Text("Open")
                            .font(.dsSansPt(14, weight: .medium))
                            .foregroundStyle(t.accentFg)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(t.accent)
                    .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                }
            }
        }
    }

    private var previewURL: String {
        if let data = artifact.payloadJSON.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let url = json["url"] as? String {
            return url
        }
        return artifact.summary ?? artifact.title
    }

    // MARK: - Approval detail

    private var approvalDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let summary = artifact.summary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("COMMAND / PATCH")
                        .font(.dsMonoPt(10, weight: .medium))
                        .foregroundStyle(t.text3)
                        .tracking(1.0)
                    Text(summary)
                        .font(.dsMonoPt(13))
                        .foregroundStyle(t.text)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(t.surfaceSunk)
                        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                                .strokeBorder(t.border, lineWidth: 1)
                        )
                }
            }
            if artifact.status == .running, let onDecision {
                HStack(spacing: 8) {
                    DSButton("Deny", variant: .destructive, size: .md, mono: true, fullWidth: true) {
                        onDecision(false)
                        dismiss()
                    }
                    DSButton("Approve", variant: .primary, size: .md, mono: true, fullWidth: true) {
                        onDecision(true)
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var formattedJSON: String {
        guard let data = artifact.payloadJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8)
        else { return artifact.payloadJSON }
        return str
    }
}

#endif
