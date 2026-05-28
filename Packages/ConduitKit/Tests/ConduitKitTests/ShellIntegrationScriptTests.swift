import Testing
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
}
