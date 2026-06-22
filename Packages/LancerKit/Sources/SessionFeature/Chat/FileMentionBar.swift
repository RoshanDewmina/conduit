#if os(iOS)
import SwiftUI
import DesignSystem

// MARK: - FileMentionBar
//
// "@" file-mention autocomplete that floats above the composer. When the trailing
// token in the prompt starts with "@", the parent fetches the workspace's files
// and passes them here; tapping inserts the path. Mirrors CommandAutocompleteBar.

public struct FileMentionBar: View {
    /// The full composer text. Active only when the trailing token starts with "@".
    private let query: String
    private let files: [String]
    private let onPick: (String) -> Void

    @Environment(\.lancerTokens) private var t

    public init(query: String, files: [String], onPick: @escaping (String) -> Void) {
        self.query = query
        self.files = files
        self.onPick = onPick
    }

    /// The trailing "@token" the user is typing, if any (nil when not mentioning).
    public static func activeToken(in text: String) -> String? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        let token = text[text.index(after: at)...]
        // A mention token has no spaces; a space ends it.
        return token.contains(" ") ? nil : String(token)
    }

    public var isActive: Bool { Self.activeToken(in: query) != nil }

    private var matches: [String] {
        guard let needle = Self.activeToken(in: query) else { return [] }
        if needle.isEmpty { return Array(files.prefix(20)) }
        let lower = needle.lowercased()
        return files.filter { $0.lowercased().contains(lower) }.prefix(20).map { $0 }
    }

    public var body: some View {
        let results = matches
        if isActive && !results.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("FILES")
                        .font(.dsMonoPt(9.5, weight: .medium))
                        .tracking(1.0)
                        .foregroundStyle(t.text4)
                        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
                    ForEach(results, id: \.self) { file in
                        Button {
                            Haptics.selection()
                            onPick(file)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: file.hasSuffix("/") ? "folder" : "doc")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(t.accent)
                                Text(file)
                                    .font(.dsMonoPt(12.5))
                                    .foregroundStyle(t.text2)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 220)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(t.border.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
        }
    }
}
#endif
