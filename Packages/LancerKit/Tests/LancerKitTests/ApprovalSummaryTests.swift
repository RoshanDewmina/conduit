import Testing
import Foundation
@testable import LancerCore

@Suite struct ApprovalSummaryTests {
    private func approval(
        kind: Approval.Kind,
        command: String? = nil,
        patch: String? = nil,
        question: String? = nil,
        blast: ApprovalBlastRadius? = nil
    ) -> Approval {
        Approval(sessionID: SessionID(), agent: .claudeCode, kind: kind,
                 command: command, patch: patch, cwd: "/repo", risk: .medium,
                 question: question, blastRadius: blast)
    }

    @Test func commandHeadlineUsesVerbAndSubcommand() {
        let s = ApprovalSummary.derive(from: approval(kind: .command, command: "git push origin main"))
        #expect(s.headline == "Runs `git push`")
    }

    @Test func plainBinaryShowsBasenameOnly() {
        let s = ApprovalSummary.derive(from: approval(kind: .command, command: "/usr/bin/rm -rf build"))
        #expect(s.headline == "Runs `rm`")
    }

    @Test func impactTagsAppendFromBlastRadius() {
        let s = ApprovalSummary.derive(from: approval(
            kind: .command, command: "curl https://x",
            blast: ApprovalBlastRadius(touchesGit: true, touchesNetwork: true)))
        #expect(s.headline == "Runs `curl` · touches git · network access")
    }

    @Test func patchCountsFilesAndLines() {
        let patch = """
        diff --git a/x.txt b/x.txt
        --- a/x.txt
        +++ b/x.txt
        +added one
        +added two
        -removed one
        """
        let s = ApprovalSummary.derive(from: approval(kind: .patch, patch: patch))
        #expect(s.headline == "Edits 1 file")
        #expect(s.facts.contains("+2 −1"))
    }

    @Test func patchFileCountPrefersBlastRadius() {
        let s = ApprovalSummary.derive(from: approval(
            kind: .patch, patch: "+a\n-b",
            blast: ApprovalBlastRadius(files: ["a.swift", "b.swift", "c.swift"])))
        #expect(s.headline == "Edits 3 files")
    }

    @Test func questionIsSummarized() {
        let s = ApprovalSummary.derive(from: approval(kind: .askQuestion, question: "Proceed with the migration?"))
        #expect(s.headline == "Asks: Proceed with the migration?")
    }

    @Test func emptyCommandFallsBack() {
        let s = ApprovalSummary.derive(from: approval(kind: .command, command: "   "))
        #expect(s.headline == "Runs a shell command")
    }
}
