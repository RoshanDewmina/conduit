import Foundation
import Testing
@testable import AppFeature

@Suite("LiveThreadCwd")
struct LiveThreadCwdTests {

    @Test("named repo maps to ~/name")
    func namedRepo() {
        #expect(LiveThreadCwd.forWorkspace("conduit") == "~/conduit")
        #expect(LiveThreadCwd.forWorkspace("personal-web") == "~/personal-web")
    }

    @Test("All Repos stays at home placeholder")
    func allRepos() {
        #expect(LiveThreadCwd.forWorkspace("All Repos") == LiveThreadCwd.homePlaceholder)
    }

    @Test("empty or whitespace workspace stays at home")
    func emptyWorkspace() {
        #expect(LiveThreadCwd.forWorkspace("") == "~")
        #expect(LiveThreadCwd.forWorkspace("   ") == "~")
    }

    @Test("identifier carries prompt and cwd")
    func identifierMapping() {
        let fixedID = UUID()
        let thread = LiveThreadIdentifier(prompt: "fix onboarding", cwd: "~/conduit", id: fixedID)
        #expect(thread.id == fixedID)
        #expect(thread.prompt == "fix onboarding")
        #expect(thread.cwd == "~/conduit")
    }
}
