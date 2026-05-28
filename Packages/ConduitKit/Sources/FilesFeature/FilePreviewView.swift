#if os(iOS)
import SwiftUI
import DesignSystem

// Syntax-light file content viewer for bottom-drawer presentation.
// Displays raw text with monospaced font + token colors.
// No external syntax-highlighting library — basic line numbers + keyword tint.

public struct FilePreviewView: View {
    let filename: String
    let content: String

    @Environment(\.conduitTokens) private var t

    public init(filename: String, content: String) {
        self.filename = filename
        self.content = content
    }

    public var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                let lines = content.components(separatedBy: "\n")
                ForEach(lines.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 0) {
                        // Line number gutter
                        Text("\(i + 1)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(t.text4)
                            .frame(width: 36, alignment: .trailing)
                            .padding(.trailing, 10)

                        // Line content
                        Text(lines[i].isEmpty ? " " : lines[i])
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(t.termText)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.vertical, 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(t.termBg)
        .navigationTitle(filename)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - BottomDrawer helper

public extension View {
    func filePreviewDrawer(
        filename: String?,
        content: String?,
        isPresented: Binding<Bool>
    ) -> some View {
        bottomDrawer(isPresented: isPresented, detents: [.medium, .large]) {
            if let name = filename, let text = content {
                FilePreviewView(filename: name, content: text)
            } else {
                ContentUnavailableView("No file", systemImage: "doc.text")
            }
        }
    }
}

#endif
