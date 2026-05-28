#if os(iOS)
import SwiftUI
import DiffKit
import DesignSystem

public struct DiffView: View {
    public let diff: UnifiedDiff
    public init(diff: UnifiedDiff) { self.diff = diff }

    @Environment(\.conduitTokens) private var t

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                // Summary header
                summaryCard
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // Per-file sections
                ForEach(diff.files) { file in
                    Section {
                        filePatchContent(file)
                    } header: {
                        fileHeader(for: file)
                    }
                }
            }
        }
        .background(t.surf0)
        .navigationTitle("Diff")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: "plus.square.fill").foregroundStyle(t.ok)
                Text("\(diff.totalAdditions)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(t.ok)
            }
            HStack(spacing: 4) {
                Image(systemName: "minus.square.fill").foregroundStyle(t.danger)
                Text("\(diff.totalDeletions)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(t.danger)
            }
            Spacer()
            DSChip("\(diff.files.count) file\(diff.files.count == 1 ? "" : "s")", tone: .neutral, style: .soft)
        }
        .padding(12)
        .background(t.surf1)
        .clipShape(RoundedRectangle(cornerRadius: t.radiusMD))
        .overlay(
            RoundedRectangle(cornerRadius: t.radiusMD)
                .strokeBorder(t.surf3, lineWidth: 0.75)
        )
    }

    // MARK: - File header

    private func fileHeader(for file: DiffKit.FilePatch) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text").font(.caption).foregroundStyle(t.text3)
            Text(file.displayPath)
                .font(.caption.monospaced().weight(.medium))
                .foregroundStyle(t.text2)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text("+\(file.additions) −\(file.deletions)")
                .font(.caption2.monospaced())
                .foregroundStyle(t.text4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(t.surf2)
    }

    // MARK: - File patch content

    @ViewBuilder
    private func filePatchContent(_ file: DiffKit.FilePatch) -> some View {
        if file.isBinary {
            Text("(binary patch)")
                .font(.caption.monospaced())
                .foregroundStyle(t.text3)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else {
            ForEach(file.hunks) { hunk in
                VStack(alignment: .leading, spacing: 0) {
                    // Hunk header
                    Text(hunk.header)
                        .font(.caption2.monospaced())
                        .foregroundStyle(t.text4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(t.surf2.opacity(0.5))

                    // Lines
                    ForEach(hunk.lines.indices, id: \.self) { i in
                        diffLine(hunk.lines[i])
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 0))
            }
        }
    }

    private func diffLine(_ line: DiffKit.Hunk.Line) -> some View {
        let (bg, fg, prefix): (Color, Color, String) = switch line.kind {
        case .addition: (t.ok.opacity(0.10),     t.ok,     "+")
        case .deletion: (t.danger.opacity(0.10), t.danger, "−")
        case .context:  (.clear,                  t.text2,  " ")
        case .noNewline:(.clear,                  t.text4,  "\\")
        }
        return HStack(spacing: 0) {
            Text(prefix)
                .foregroundStyle(fg)
                .frame(width: 16, alignment: .leading)
            Text(line.text)
                .foregroundStyle(fg == t.text2 ? t.text2 : fg.opacity(0.85))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, 12)
        .padding(.vertical, 1)
        .background(bg)
    }
}

// MARK: - BottomDrawer presentation helper

public extension View {
    /// Present a DiffView in a bottom drawer from any view.
    func diffDrawer(diff: UnifiedDiff?, isPresented: Binding<Bool>) -> some View {
        bottomDrawer(isPresented: isPresented, detents: [.medium, .large]) {
            if let d = diff {
                DiffView(diff: d)
            } else {
                ContentUnavailableView("No diff", systemImage: "plusminus")
            }
        }
    }
}

#endif
