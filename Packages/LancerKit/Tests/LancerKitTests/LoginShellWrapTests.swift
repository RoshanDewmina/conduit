import Testing
@testable import SSHTransport

@Suite("SSHSession.loginShellWrap")
struct LoginShellWrapTests {

    @Test("plain command is wrapped in login-shell invocation")
    func plainCommandWrap() {
        let result = SSHSession.loginShellWrap("brew install curl")
        #expect(result == "${SHELL:-/bin/sh} -lc 'brew install curl'")
    }

    @Test("command with single quotes is POSIX-escaped")
    func singleQuoteEscape() {
        // The `'` in `echo 'hi'` must become '\'' so the outer single-quoted
        // shell argument stays syntactically valid.
        let result = SSHSession.loginShellWrap("echo 'hi'")
        #expect(result == #"${SHELL:-/bin/sh} -lc 'echo '\''hi'\'''"#)
    }

    @Test("command with double-dollar keeps dollar signs")
    func dollarSign() {
        let result = SSHSession.loginShellWrap("echo $HOME")
        // $HOME must NOT expand when inside single quotes.
        #expect(result == "${SHELL:-/bin/sh} -lc 'echo $HOME'")
    }

    @Test("command with backtick does not expand")
    func backtick() {
        let result = SSHSession.loginShellWrap("echo `whoami`")
        #expect(result == "${SHELL:-/bin/sh} -lc 'echo `whoami`'")
    }

    @Test("empty command wraps safely")
    func emptyCommand() {
        let result = SSHSession.loginShellWrap("")
        #expect(result == "${SHELL:-/bin/sh} -lc ''")
    }
}
