#if os(iOS)
import SwiftUI
import UIKit
import DesignSystem

// MARK: - Fenced code block card
//
// A ```fenced``` block from an assistant message, rendered on the dark terminal
// palette (matching DarkTerminalBlockCard) with a language label and a copy
// button. Horizontal scroll keeps long lines from wrapping into mush; the "wrap"
// toggle is for when you'd rather read than scroll.

public struct DarkCodeCard: View {
    private let language: String?
    private let code: String

    @State private var wrap = false
    @State private var copied = false
    @Environment(\.lancerTokens) private var t

    public init(language: String?, code: String) {
        self.language = language
        self.code = code
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            codeBody
        }
        .background(t.termBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(t.termText3.opacity(0.18), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(language?.isEmpty == false ? language!.lowercased() : "code")
                .font(.dsMonoPt(10.5, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(t.termText3)
            Spacer(minLength: 0)
            Button {
                Haptics.selection()
                wrap.toggle()
            } label: {
                Image(systemName: wrap ? "arrow.right.to.line" : "text.alignleft")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(t.termText3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(wrap ? "Scroll long lines" : "Wrap long lines")
            Button {
                UIPasteboard.general.string = code
                Haptics.success()
                withAnimation { copied = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    await MainActor.run { withAnimation { copied = false } }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                    Text(copied ? "Copied" : "Copy")
                        .font(.dsMonoPt(10.5, weight: .medium))
                }
                .foregroundStyle(copied ? t.termOk : t.termText3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy code")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(t.termSurface2)
    }

    @ViewBuilder
    private var codeBody: some View {
        let highlighted = SyntaxHighlighter.highlight(
            code, keyword: t.termAccent, string: t.termOk, comment: t.termText3, base: t.termText2
        )
        let text = Text(highlighted)
            .font(.dsMonoPt(12.5))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)

        if wrap {
            text
        } else {
            ScrollView(.horizontal, showsIndicators: false) { text }
        }
    }
}
#endif
