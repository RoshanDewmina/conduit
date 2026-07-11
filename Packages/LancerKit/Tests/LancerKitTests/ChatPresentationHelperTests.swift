import Testing
import Foundation
@testable import AppFeature

@Suite struct ChatPresentationHelperTests {

    // MARK: - DiffCountFormat

    @Test func diffCountLabels() {
        let format = DiffCountFormat(added: 858, removed: 38)
        #expect(format.addedLabel == "+858")
        #expect(format.removedLabel == "-38")
        #expect(format.combinedLabel == "+858 -38")
    }

    @Test func diffCountClampsNegative() {
        let format = DiffCountFormat(added: -3, removed: -1)
        #expect(format.addedLabel == "+0")
        #expect(format.removedLabel == "-0")
    }

    // MARK: - ChatMarkdownPreprocessor

    @Test func preprocessNormalizesUnicodeBullets() {
        let input = "Notes:\n• first\n● second\n◦ third"
        let out = ChatMarkdownPreprocessor.preprocess(input)
        #expect(out.contains("- first"))
        #expect(out.contains("- second"))
        #expect(out.contains("- third"))
        #expect(!out.contains("•"))
    }

    @Test func preprocessNormalizesAsteriskBulletsButKeepsBold() {
        let input = "* item\n**bold stays**"
        let out = ChatMarkdownPreprocessor.preprocess(input)
        #expect(out.contains("- item"))
        #expect(out.contains("**bold stays**"))
    }

    @Test func preprocessConvertsDetailsSummaryToBoldVisibleBody() {
        let input = """
        <details><summary>Answers</summary>
        13 ✓
        **Quick vocabulary**
        **Variable** — a symbol for a number
        **Coefficient** — number multiplying a variable
        </details>
        """
        let out = ChatMarkdownPreprocessor.preprocess(input)
        #expect(!out.contains("<details"))
        #expect(!out.contains("<summary"))
        #expect(!out.contains("</details>"))
        #expect(out.contains("**Answers**"))
        #expect(out.contains("13 ✓"))
        #expect(out.contains("**Quick vocabulary**"))
        #expect(out.contains("**Variable**"))
        #expect(out.contains("**Coefficient**"))
    }

    @Test func preprocessConvertsCommonHTMLTags() {
        let input = #"<b>Bold</b> <i>Italic</i><br>line<code>x</code><pre>a = 1</pre>"#
        let out = ChatMarkdownPreprocessor.preprocess(input)
        #expect(out.contains("**Bold**"))
        #expect(out.contains("*Italic*"))
        #expect(out.contains("`x`"))
        #expect(out.contains("```"))
        #expect(out.contains("a = 1"))
        #expect(!out.contains("<b>"))
        #expect(!out.contains("<br"))
    }

    @Test func preprocessStripsUnknownTagsKeepsContent() {
        let out = ChatMarkdownPreprocessor.preprocess(#"Hello <span class="x">world</span>!"#)
        #expect(out.contains("Hello world!"))
        #expect(!out.contains("<span"))
    }

    @Test func preprocessInsertsBlankLinesBetweenHeadingsAndBoldLeads() {
        // Owner dogfood fixture: adjacent headings / bold terms collapsed visually.
        let input = """
        ## Systems
        ## Beginnings:
        13 ✓
        **Quick vocabulary**
        **Variable** — symbol
        **Coefficient** — multiplier
        """
        let out = ChatMarkdownPreprocessor.preprocess(input)
        #expect(out.contains("## Systems\n\n## Beginnings:"))
        #expect(out.contains("**Quick vocabulary**\n\n**Variable**"))
        #expect(out.contains("**Variable** — symbol\n\n**Coefficient**"))
    }

    @Test func attributedStringPreservesBlockSeparationFromOwnerFixture() {
        let input = """
        ## Systems
        ## Beginnings:
        **Quick vocabulary**
        **Variable** — symbol
        """
        let attr = ChatMarkdownAttributedString.make(from: input)
        let plain = String(attr.characters)
        #expect(plain.contains("Systems"))
        #expect(plain.contains("Beginnings:"))
        // Must not glue heading text the way raw Foundation markdown does.
        #expect(!plain.contains("SystemsBeginnings"))
        #expect(!plain.contains("vocabularyVariable"))
        #expect(plain.contains("\n"))
    }

    // MARK: - ChatMarkdownBlockParser

    @Test func parseSplitsProseAndFences() {
        let md = """
        Hello `inline`

        ```swift
        let x = 1
        ```

        After
        """
        let blocks = ChatMarkdownBlockParser.parse(md)
        #expect(blocks.count == 3)
        guard case .prose(let prose1) = blocks[0] else {
            Issue.record("expected prose"); return
        }
        #expect(prose1.contains("Hello"))
        guard case .codeFence(let lang, let code) = blocks[1] else {
            Issue.record("expected fence"); return
        }
        #expect(lang == "swift")
        #expect(code == "let x = 1")
        guard case .prose(let prose2) = blocks[2] else {
            Issue.record("expected trailing prose"); return
        }
        #expect(prose2.contains("After"))
    }

    @Test func parsePlainProseOnly() {
        let blocks = ChatMarkdownBlockParser.parse("Just text with `code`")
        #expect(blocks.count == 1)
        guard case .prose = blocks[0] else {
            Issue.record("expected single prose block"); return
        }
    }

    @Test func parseEmptyYieldsEmpty() {
        #expect(ChatMarkdownBlockParser.parse("").isEmpty)
    }

    // MARK: - ChatMarkdownAttributedString

    @Test func attributedStringMarksInlineCode() {
        let attr = ChatMarkdownAttributedString.make(from: "Use `PermissionCoordinator` here")
        let ranges = ChatMarkdownAttributedString.inlineCodeRanges(in: attr)
        #expect(!ranges.isEmpty)
        let joined = ranges.map { String(attr[$0].characters) }.joined()
        #expect(joined.contains("PermissionCoordinator"))
    }

    @Test func attributedStringFallsBackOnEmpty() {
        let attr = ChatMarkdownAttributedString.make(from: "")
        #expect(String(attr.characters).isEmpty)
    }

    // MARK: - ChatFileNameDisplay

    @Test func truncatesLongNamesInMiddle() {
        let name = "2026-07-04-device-handoff-approval-security.md"
        let truncated = ChatFileNameDisplay.truncated(name, maxLength: 28)
        #expect(truncated.count == 28)
        #expect(truncated.contains("…"))
        #expect(truncated.hasPrefix("2026"))
        #expect(truncated.hasSuffix(".md"))
    }

    @Test func shortNamesUnchanged() {
        #expect(ChatFileNameDisplay.truncated("short.swift") == "short.swift")
    }

    @Test func displayNameUsesBasename() {
        #expect(ChatFileNameDisplay.displayName(for: "daemon/lancerd/foo.go") == "foo.go")
        #expect(ChatFileNameDisplay.displayName(for: "foo.go") == "foo.go")
    }

    // MARK: - ChangedFile

    @Test func changedFileExposesDiffFormat() {
        let file = ChangedFile(badge: "SW", name: "A.swift", added: 10, removed: 2)
        #expect(file.diff.combinedLabel == "+10 -2")
    }
}
