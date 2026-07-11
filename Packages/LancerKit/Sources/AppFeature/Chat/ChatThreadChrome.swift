#if os(iOS)
import SwiftUI
import UIKit

/// Renders assistant markdown as plain body text (not a bubble): prose via native
/// `AttributedString(markdown:)` with inline-code chips, plus fenced blocks with copy.
struct ChatMarkdownBody: View {
    let markdown: String
    var bodyFontSize: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(ChatMarkdownBlockParser.parse(markdown).enumerated()), id: \.offset) { _, block in
                switch block {
                case .prose(let text):
                    proseView(text)
                case .codeFence(let language, let code):
                    ChatCodeFenceBlock(language: language, code: code)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func proseView(_ text: String) -> some View {
        Text(styledProse(text))
            .font(.system(size: bodyFontSize))
            .foregroundStyle(.primary)
            .lineSpacing(4)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func styledProse(_ text: String) -> AttributedString {
        var attributed = ChatMarkdownAttributedString.make(from: text)
        let chip = UIColor.tertiarySystemFill
        for range in ChatMarkdownAttributedString.inlineCodeRanges(in: attributed) {
            attributed[range].backgroundColor = chip
            attributed[range].font = UIFont.monospacedSystemFont(ofSize: bodyFontSize - 1, weight: .regular)
        }
        return attributed
    }
}

/// Fenced code block: monospace body + copy affordance (Cursor chat pattern).
struct ChatCodeFenceBlock: View {
    let language: String?
    let code: String
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text((language?.isEmpty == false) ? (language ?? "code") : "code")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    didCopy = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        didCopy = false
                    }
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(didCopy ? "Copied" : "Copy code"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }
}

/// Right-aligned quiet user bubble (Cursor reference: muted fill, no accent color).
struct ChatUserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemFill))
                )
        }
    }
}

/// Green/red +/− counts as a single `Text` (shared by Changes rows and View PR pills).
func chatDiffStatText(added: Int, removed: Int) -> Text {
    let format = DiffCountFormat(added: added, removed: removed)
    var addedText = AttributedString(format.addedLabel)
    addedText.foregroundColor = Color.green
    var removedText = AttributedString(" \(format.removedLabel)")
    removedText.foregroundColor = Color.red
    return Text(addedText + removedText)
}

/// Cursor-style Changes card: header count + file rows with doc icon and +/−.
struct ChatChangesCard: View {
    let files: [ChangedFile]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Changes")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(files.count)")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            ForEach(Array(files.enumerated()), id: \.offset) { index, file in
                HStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    Text(file.name)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 8)

                    chatDiffStatText(added: file.added, removed: file.removed)
                        .font(.system(size: 14, design: .monospaced))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                if index < files.count - 1 {
                    Divider()
                        .padding(.leading, 44)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }
}

/// Capsule outline pill used for View PR / Mark Ready.
struct ChatOutlinePillLabel: View {
    let title: String
    var added: Int? = nil
    var removed: Int? = nil
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            if let added, let removed {
                chatDiffStatText(added: added, removed: removed)
                    .font(.system(size: 14, design: .monospaced))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
        .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 0.5))
    }
}

/// Decorative docked "Follow up…" bar (+ / placeholder / mic) for historical threads.
struct ChatFollowUpPlaceholderBar: View {
    var placeholder: String = "Follow up…"

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .strokeBorder(Color(.separator), lineWidth: 1)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                )

            Text(placeholder)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Image(systemName: "mic.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
        .overlay(Capsule().strokeBorder(Color(.separator).opacity(0.6), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Follow up"))
    }
}

/// Live follow-up composer styled like Cursor's docked bar; keeps TextField + send path.
struct ChatFollowUpComposerBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var placeholder: String = "Follow up…"
    var isDisabled: Bool = false
    var canSend: Bool = false
    var onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .strokeBorder(Color(.separator), lineWidth: 1)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                )
                .accessibilityHidden(true)

            TextField(placeholder, text: $text)
                .font(.system(size: 16))
                .focused(isFocused)
                .disabled(isDisabled)
                .submitLabel(.send)
                .onSubmit {
                    guard canSend else { return }
                    onSend()
                }

            if canSend {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(!canSend || isDisabled)
                .accessibilityLabel(Text("Send"))
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
        .overlay(Capsule().strokeBorder(Color(.separator).opacity(0.6), lineWidth: 0.5))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
#endif
