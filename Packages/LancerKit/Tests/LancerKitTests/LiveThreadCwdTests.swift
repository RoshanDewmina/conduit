import Foundation
import Testing
@testable import AppFeature

@Suite("LiveThreadIdentifier")
struct LiveThreadCwdTests {

    @Test("identifier carries prompt and cwd without name→~/name mapping")
    func identifierMapping() {
        let fixedID = UUID()
        let thread = LiveThreadIdentifier(prompt: "fix onboarding", cwd: "/Users/dev/conduit", id: fixedID)
        #expect(thread.id == fixedID)
        #expect(thread.prompt == "fix onboarding")
        #expect(thread.cwd == "/Users/dev/conduit")
    }
}
