#if os(iOS)
import SwiftUI
import DesignSystem

public struct TextPreview: View {
    public let filename: String
    public let data: Data

    public init(filename: String, data: Data) {
        self.filename = filename
        self.data = data
    }

    private var text: String? {
        // A NUL byte means binary content; ISO-Latin-1 decodes every byte, so
        // without this guard the "Binary file" placeholder below is unreachable.
        if data.contains(0) { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    public var body: some View {
        Group {
            if let text {
                ScrollView {
                    Text(text)
                        .font(.dsMono(.caption))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding()
                        .textSelection(.enabled)
                }
            } else {
                ContentUnavailableView(
                    "Binary file",
                    systemImage: "doc.zipper",
                    description: Text(
                        ByteCountFormatter.string(
                            fromByteCount: Int64(data.count),
                            countStyle: .file
                        )
                    )
                )
            }
        }
        .navigationTitle(filename)
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
