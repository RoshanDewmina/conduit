import Testing
import Foundation
@testable import TerminalEngine

@Suite("AnsiSGRParser")
struct AnsiSGRParserTests {

    @Test("plain text emits with no attributes")
    func plain() {
        let parser = AnsiSGRParser()
        let (out, state) = parser.parse("hello world")
        #expect(String(out.characters) == "hello world")
        #expect(state == .init())
    }

    @Test("reset SGR clears state")
    func reset() {
        let parser = AnsiSGRParser()
        var (out, state) = parser.parse("\u{1B}[31mred ")
        #expect(state.foreground != nil)
        (out, state) = parser.parse("\u{1B}[0mback", inheriting: state)
        #expect(state == .init())
        _ = out
    }

    @Test("16-color sequence sets foreground")
    func ansi16() {
        let parser = AnsiSGRParser()
        let (_, state) = parser.parse("\u{1B}[32mgreen")
        #expect(state.foreground != nil)
    }

    @Test("256-color sequence sets foreground")
    func ansi256() {
        let parser = AnsiSGRParser()
        let (_, state) = parser.parse("\u{1B}[38;5;202mneon")
        #expect(state.foreground != nil)
    }

    @Test("truecolor sequence sets foreground")
    func truecolor() {
        let parser = AnsiSGRParser()
        let (_, state) = parser.parse("\u{1B}[38;2;255;100;50mhot")
        #expect(state.foreground != nil)
    }

    @Test("alt-screen escalates to TUI mode")
    func tuiDetector() {
        let data = Data("\u{1B}[?1049h".utf8)
        #expect(TUIDetector.shouldEscalate(to: data))
    }

    @Test("cursor-positioning escalates inline TUI mode")
    func cursorPositioningDetector() {
        let data = Data("\u{1B}[2J\u{1B}[H\u{1B}[?25lClaude".utf8)
        #expect(TUIDetector.shouldEscalate(to: data))
    }

    @Test("plain output does not escalate")
    func tuiNegative() {
        let data = Data("hello\n".utf8)
        #expect(!TUIDetector.shouldEscalate(to: data))
    }
}
