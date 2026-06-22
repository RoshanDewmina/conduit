import Testing
import DiffKit

struct PatchDiffRenderTests {
    @Test func parsesAUnifiedPatch() {
        let patch = """
        --- a/foo.txt
        +++ b/foo.txt
        @@ -1,2 +1,2 @@
        -old line
        +new line
         context
        """
        let diff = UnifiedDiffParser.parse(patch)
        #expect(!diff.files.isEmpty)
    }
}
