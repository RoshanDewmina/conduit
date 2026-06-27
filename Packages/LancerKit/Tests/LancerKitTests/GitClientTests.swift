import Testing
import Foundation
@testable import SSHTransport

@Suite("GitClient parsing")
struct GitClientTests {
    @Test("parses branch, upstream, ahead/behind and changes")
    func parseStatusFull() {
        let output = """
        ## feature/login...origin/feature/login [ahead 2, behind 1]
         M Sources/App/Login.swift
        A  Sources/App/New.swift
        ?? notes.txt
        R  old/path.swift -> new/path.swift
        """
        let status = GitClient.parseStatus(output)
        #expect(status.branch == "feature/login")
        #expect(status.upstream == "origin/feature/login")
        #expect(status.ahead == 2)
        #expect(status.behind == 1)
        #expect(status.changes.count == 4)

        #expect(status.changes[0].path == "Sources/App/Login.swift")
        #expect(status.changes[0].staged == false)      // " M" — worktree only
        #expect(status.changes[0].label == "modified")

        #expect(status.changes[1].staged == true)       // "A " — staged add
        #expect(status.changes[1].label == "added")

        #expect(status.changes[2].path == "notes.txt")
        #expect(status.changes[2].staged == false)      // "??" untracked
        #expect(status.changes[2].label == "untracked")

        #expect(status.changes[3].path == "new/path.swift")  // rename → new path
        #expect(status.changes[3].label == "renamed")
        #expect(!status.isClean)
        #expect(status.hasStagedChanges)
    }

    @Test("clean tree with no upstream")
    func parseStatusClean() {
        let status = GitClient.parseStatus("## main\n")
        #expect(status.branch == "main")
        #expect(status.upstream == nil)
        #expect(status.ahead == 0)
        #expect(status.behind == 0)
        #expect(status.isClean)
        #expect(!status.hasStagedChanges)
    }

    @Test("splitExit separates trailing exit marker")
    func splitExitParsing() {
        let raw = "fatal: not a git repository\n__LANCER_GIT_EXIT__128"
        let (output, code) = GitClient.splitExit(raw)
        #expect(output == "fatal: not a git repository")
        #expect(code == 128)
    }

    @Test("splitExit defaults to 0 when marker absent")
    func splitExitNoMarker() {
        let (output, code) = GitClient.splitExit("plain output")
        #expect(output == "plain output")
        #expect(code == 0)
    }

    @Test("shellQuote escapes embedded single quotes")
    func shellQuoteEscaping() {
        #expect(GitClient.shellQuote("simple") == "'simple'")
        // Injection attempt stays inside the quoted literal.
        #expect(GitClient.shellQuote("a'; rm -rf /") == "'a'\\''; rm -rf /'")
    }

    @Test("numstat totals include text files and keep binary files countable")
    func parseNumstat() {
        let summary = GitClient.parseNumstat("12\t3\tSources/App.swift\n-\t-\tAssets/logo.png\n0\t1\tREADME.md\n")
        #expect(summary.additions == 12)
        #expect(summary.deletions == 4)
        #expect(summary.changedFiles == 3)
    }
}
