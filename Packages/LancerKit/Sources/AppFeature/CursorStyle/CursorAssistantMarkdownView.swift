#if os(iOS)
import SwiftUI
import MarkdownUI
import DesignSystem

/// Renders assistant/error transcript text through MarkdownUI, themed from
/// `CursorColors`/`CursorType`, with a per-code-block copy button.
///
/// Ported: code-block copy-with-check-state pattern from Happier (MIT)
/// `components/ui/code/blocks/CodeBlockViewFrame.tsx:41,66-81` — reuses the existing
/// `CursorCopiedToast` for the check-state instead of an inline icon swap.
struct CursorAssistantMarkdownView: View {
    @Environment(\.cursorScheme) private var cursorScheme

    let text: String
    let onCopyCodeBlock: (String) -> Void

    private var colors: CursorColors { CursorColors.resolve(cursorScheme) }

    var body: some View {
        Markdown(CursorMarkdownPreprocessor.preprocess(text))
            .markdownTheme(theme)
            .markdownBlockStyle(\.codeBlock) { configuration in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        if let language = configuration.language, !language.isEmpty {
                            Text(language)
                                .font(CursorType.diffLineNumber)
                                .foregroundColor(colors.mutedText)
                        }
                        Spacer()
                        Button {
                            onCopyCodeBlock(configuration.content)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(colors.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Copy code")
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    configuration.label
                        .relativeLineSpacing(.em(0.1))
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(.em(0.9))
                        }
                        .padding(10)
                }
                .background(colors.codeBlockBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(colors.hairline, lineWidth: 0.5)
                )
            }
    }

    private var theme: Theme {
        Theme()
            .text {
                ForegroundColor(colors.primaryText)
                FontSize(16)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.9))
                ForegroundColor(colors.primaryText)
                BackgroundColor(colors.codeBlockBackground)
            }
            .link {
                ForegroundColor(colors.orangeAccent)
            }
            .paragraph { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.2))
                    .markdownMargin(top: 0, bottom: 8)
            }
    }
}
#endif
