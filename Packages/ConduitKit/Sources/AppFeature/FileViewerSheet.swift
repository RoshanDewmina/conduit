#if os(iOS)
import SwiftUI
import DesignSystem

public struct FileViewerSheet: View {
    public let filePath: String
    public let content: String
    public let language: String?

    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    public init(filePath: String, content: String, language: String? = nil) {
        self.filePath = filePath
        self.content = content
        self.language = language
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    DSIconView(.file, size: 14, color: t.text3)
                    Text(filePath)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(t.surface)

                ScrollView([.horizontal, .vertical]) {
                    Text(content)
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text2)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(t.surfaceSunk)
            }
            .background(t.bg)
            .navigationTitle(URL(fileURLWithPath: filePath).lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        UIPasteboard.general.string = content
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copied = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            DSIconView(copied ? .check : .copy, size: 13, color: copied ? t.accent : t.text2)
                            Text(copied ? "Copied" : "Copy")
                                .font(.dsMonoPt(11))
                                .foregroundStyle(copied ? t.accent : t.text2)
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(.dsSansPt(14))
                        .foregroundStyle(t.text2)
                }
            }
        }
    }
}
#endif
