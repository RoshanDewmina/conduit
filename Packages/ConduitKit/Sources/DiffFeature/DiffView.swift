#if os(iOS)
import SwiftUI
import DiffKit
import DesignSystem

public struct DiffView: View {
    public let diff: UnifiedDiff
    public init(diff: UnifiedDiff) { self.diff = diff }

    public var body: some View {
        List {
            Section {
                HStack {
                    Label("\(diff.totalAdditions)", systemImage: "plus.square")
                        .foregroundStyle(.green)
                    Label("\(diff.totalDeletions)", systemImage: "minus.square")
                        .foregroundStyle(.red)
                    Spacer()
                    Text("\(diff.files.count) file(s)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(diff.files) { file in
                Section(header: header(for: file)) {
                    if file.isBinary {
                        Text("(binary patch)").foregroundStyle(.secondary)
                    } else {
                        ForEach(file.hunks) { hunk in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hunk.header)
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                                ForEach(hunk.lines.indices, id: \.self) { i in
                                    line(hunk.lines[i])
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Diff")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func header(for file: DiffKit.FilePatch) -> some View {
        HStack {
            Text(file.displayPath).font(.callout.monospaced())
            Spacer()
            Text("+\(file.additions) −\(file.deletions)")
                .font(.caption2.monospaced()).foregroundStyle(.secondary)
        }
    }

    private func line(_ line: DiffKit.Hunk.Line) -> some View {
        let (bg, fg, prefix): (Color, Color, String) = switch line.kind {
        case .addition: (Color.green.opacity(0.12),  .green,  "+")
        case .deletion: (Color.red.opacity(0.12),    .red,    "−")
        case .context:  (.clear,                     .primary, " ")
        case .noNewline: (.clear,                    .secondary, "\\")
        }
        return HStack(spacing: 0) {
            Text(prefix).foregroundStyle(fg)
            Text(line.text).foregroundStyle(.primary).textSelection(.enabled)
            Spacer()
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, 4).padding(.vertical, 1)
        .background(bg)
    }
}

#endif
