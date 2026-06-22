import Testing
@testable import DiffKit

@Suite("UnifiedDiffParser")
struct UnifiedDiffParserTests {

    @Test("parses a one-file, one-hunk patch")
    func single() {
        let diff = """
        diff --git a/foo.txt b/foo.txt
        --- a/foo.txt
        +++ b/foo.txt
        @@ -1,3 +1,3 @@
         line a
        -line b
        +line B
         line c
        """
        let parsed = UnifiedDiffParser.parse(diff)
        #expect(parsed.files.count == 1)
        let file = parsed.files[0]
        #expect(file.newPath == "foo.txt")
        #expect(file.additions == 1)
        #expect(file.deletions == 1)
        #expect(file.hunks.count == 1)
    }

    @Test("handles binary diff marker")
    func binary() {
        let diff = """
        diff --git a/img.png b/img.png
        Binary files a/img.png and b/img.png differ
        """
        let parsed = UnifiedDiffParser.parse(diff)
        #expect(parsed.files.count == 1)
        #expect(parsed.files[0].isBinary)
    }

    @Test("handles /dev/null for added files")
    func added() {
        let diff = """
        diff --git a/new.txt b/new.txt
        --- /dev/null
        +++ b/new.txt
        @@ -0,0 +1,1 @@
        +hello
        """
        let parsed = UnifiedDiffParser.parse(diff)
        #expect(parsed.files.count == 1)
        #expect(parsed.files[0].oldPath == nil)
        #expect(parsed.files[0].newPath == "new.txt")
        #expect(parsed.files[0].additions == 1)
    }
}
