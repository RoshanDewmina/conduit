import Testing
import Foundation
@testable import TerminalEngine

@Suite("ShellIntegrationScript")
struct ShellIntegrationScriptTests {

    @Test("bundled scripts emit OSC 133 and OSC 7 markers")
    func bundledScriptsEmitMarkers() {
        for shell in ShellIntegrationScript.Shell.allCases {
            let script = ShellIntegrationScript.script(for: shell)
            #expect(script.contains("133;D"))
            #expect(script.contains("133;A"))
            #expect(script.contains("133;C"))
            #expect(script.contains("file://"))
        }
    }

    @Test("POSIX bootstrap includes bash and zsh branches")
    func posixBootstrapIncludesExpectedShells() {
        let script = ShellIntegrationScript.bootstrapForPOSIXShells()
        #expect(script.contains("ZSH_VERSION"))
        #expect(script.contains("BASH_VERSION"))
        #expect(script.contains("add-zsh-hook"))
        #expect(script.contains("PROMPT_COMMAND"))
    }

    @Test("POSIX bootstrap injects COLORFGBG for dark-mode theme hint")
    func posixBootstrapContainsCOLORFGBG() {
        let script = ShellIntegrationScript.bootstrapForPOSIXShells()
        #expect(script.contains("COLORFGBG"),
                "POSIX bootstrap must export COLORFGBG so remote agents (claude/codex) auto-pick dark scheme")
    }

    @Test("colorfgbgExport returns 15;0 for dark themes and 0;15 for light")
    func colorfgbgExportValues() {
        // Default (no UserDefaults key set) → dark → "15;0"
        UserDefaults.standard.removeObject(forKey: "terminalTheme")
        let dark = ShellIntegrationScript.colorfgbgExport()
        #expect(dark.contains("15;0"), "Dark theme must export COLORFGBG='15;0'")

        // Light theme
        UserDefaults.standard.set("Light", forKey: "terminalTheme")
        let light = ShellIntegrationScript.colorfgbgExport()
        #expect(light.contains("0;15"), "Light theme must export COLORFGBG='0;15'")

        // Reset
        UserDefaults.standard.removeObject(forKey: "terminalTheme")
    }

    @Test("fish bundled script contains COLORFGBG hint")
    func fishScriptContainsCOLORFGBG() {
        let script = ShellIntegrationScript.script(for: .fish)
        #expect(script.contains("COLORFGBG"),
                "Fish integration script must set COLORFGBG so remote claude/codex auto-picks dark scheme")
    }
}
