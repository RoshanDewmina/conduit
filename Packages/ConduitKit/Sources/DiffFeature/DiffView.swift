#if os(iOS)
import SwiftUI
import DiffKit
import DesignSystem

public struct DiffView: View {
    public let diff: UnifiedDiff
    public init(diff: UnifiedDiff) { self.diff = diff }

    @Environment(\.conduitTokens) private var t

    public var body: some View {
        VStack(spacing: 0) {
            header
            DSDivider(.strong)
            content
        }
        .background(t.termBg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 0) {
                    Text("diff")
                        .font(.dsDisplayPt(22, weight: .bold))
                        .foregroundStyle(t.termText)
                    Text("_")
                        .font(.dsDisplayPt(22, weight: .bold))
                        .foregroundStyle(t.accent)
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                summaryChip
            }
            statsRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var summaryChip: some View {
        HStack(spacing: 6) {
            Text("\(diff.files.count) file\(diff.files.count == 1 ? "" : "s")")
                .font(.dsMonoPt(11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(t.termSurface)
        .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                .strokeBorder(t.termBorder, lineWidth: 1))
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(diff.totalAdditions)")
                    .font(.dsMonoPt(12, weight: .semibold))
            }
            .foregroundStyle(t.termOk)

            HStack(spacing: 6) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(t.termErr)

            Text("\(diff.totalDeletions)")
                .font(.dsMonoPt(12, weight: .semibold))
                .foregroundStyle(t.termErr)
            Spacer()
        }
        .font(.dsMonoPt(11))
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(diff.files) { file in
                    Section {
                        filePatchContent(file)
                    } header: {
                        fileHeader(for: file)
                    }
                }
            }
        }
    }

    private func fileHeader(for file: DiffKit.FilePatch) -> some View {
        HStack(spacing: 10) {
            DSIconView(.file, size: 13, color: t.termText2)
            Text(file.displayPath)
                .font(.dsMonoPt(12, weight: .medium))
                .foregroundStyle(t.termText2)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text("+\(file.additions) −\(file.deletions)")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.termText3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(t.termSurface)
    }

    @ViewBuilder
    private func filePatchContent(_ file: DiffKit.FilePatch) -> some View {
        if file.isBinary {
            Text("(binary patch)")
                .font(.dsMonoPt(12))
                .foregroundStyle(t.termText3)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        } else {
            ForEach(file.hunks) { hunk in
                VStack(alignment: .leading, spacing: 0) {
                    Text(hunk.header)
                        .font(.dsMonoPt(10))
                        .foregroundStyle(t.termText3)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(t.termSurface2.opacity(0.5))

                    ForEach(hunk.lines.indices, id: \.self) { i in
                        diffLine(hunk.lines[i])
                    }
                }
            }
        }
    }

    private func diffLine(_ line: DiffKit.Hunk.Line) -> some View {
        let (bg, fg, prefix): (Color, Color, String) = switch line.kind {
        case .addition: (t.termOk.opacity(0.08),     t.termOk,     "+")
        case .deletion: (t.termErr.opacity(0.08),    t.termErr,    "−")
        case .context:  (.clear,                      t.termText2,  " ")
        case .noNewline:(.clear,                      t.termText3,  "\\")
        }
        return HStack(spacing: 0) {
            Text(prefix)
                .foregroundStyle(fg)
                .frame(width: 20, alignment: .leading)
            Text(line.text)
                .foregroundStyle(fg == t.termText2 ? t.termText2 : fg.opacity(0.85))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.dsMonoPt(12))
        .padding(.horizontal, 16)
        .padding(.vertical, 1)
        .background(bg)
    }
}

// MARK: - BottomDrawer presentation helper

public extension View {
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
