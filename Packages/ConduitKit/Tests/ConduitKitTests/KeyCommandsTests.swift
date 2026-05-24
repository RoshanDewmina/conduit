import Testing
#if canImport(UIKit)
import UIKit
#endif
@testable import SessionFeature

@Suite("KeyCommands")
struct KeyCommandsTests {
#if os(iOS)
    @Test("Ctrl-C maps to 0x03")
    func ctrlC() {
        let bytes = ShellKeyCommand.bytes(for: "c", modifiers: .control)
        #expect(bytes == [0x03])
    }

    @Test("Ctrl-A maps to 0x01")
    func ctrlA() {
        let bytes = ShellKeyCommand.bytes(for: "a", modifiers: .control)
        #expect(bytes == [0x01])
    }

    @Test("Cmd-K maps to clear screen")
    func cmdK() {
        let bytes = ShellKeyCommand.bytes(for: "k", modifiers: .command)
        #expect(bytes == [0x0C])
    }

    @Test("all shell key bindings have valid inputs")
    func allBindingsNonEmpty() {
        for binding in ShellKeyCommand.all {
            #expect(!binding.input.isEmpty)
        }
    }

    @Test("Ctrl-D maps to 0x04 (EOF)")
    func ctrlD() {
        let bytes = ShellKeyCommand.bytes(for: "d", modifiers: .control)
        #expect(bytes == [0x04])
    }

    @Test("Ctrl-L maps to 0x0C (clear)")
    func ctrlL() {
        let bytes = ShellKeyCommand.bytes(for: "l", modifiers: .control)
        #expect(bytes == [0x0C])
    }

    @Test("Ctrl-E maps to 0x05 (line end)")
    func ctrlE() {
        let bytes = ShellKeyCommand.bytes(for: "e", modifiers: .control)
        #expect(bytes == [0x05])
    }

    @Test("Cmd-T returns nil (app-level action, no PTY bytes)")
    func cmdT() {
        let bytes = ShellKeyCommand.bytes(for: "t", modifiers: .command)
        #expect(bytes == nil)
    }

    @Test("Unknown combo returns nil")
    func unknownCombo() {
        let bytes = ShellKeyCommand.bytes(for: "x", modifiers: .command)
        #expect(bytes == nil)
    }

    @Test("All bindings have non-empty titles")
    func allBindingsHaveTitles() {
        for binding in ShellKeyCommand.all {
            #expect(!binding.title.isEmpty)
        }
    }
#endif
}
