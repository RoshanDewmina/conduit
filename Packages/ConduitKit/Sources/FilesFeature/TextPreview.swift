#if os(iOS)
import SwiftUI

public struct TextPreview: View {
    public let filename: String
    public let data: Data

    public init(filename: String, data: Data) {
        self.filename = filename
        self.data = data
    }

    private var text: String? {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    public var body: some View {
        Group {
            if let text {
                ScrollView {
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
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
