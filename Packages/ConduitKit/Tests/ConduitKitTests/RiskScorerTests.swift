import Testing
@testable import AgentKit
@testable import ConduitCore

@Suite("RiskScorer")
struct RiskScorerTests {

    @Test("read-only is low")
    func low() {
        #expect(RiskScorer.score(command: "ls -la") == .low)
        #expect(RiskScorer.score(command: "git status") == .low)
        #expect(RiskScorer.score(command: "rg foo src/") == .low)
    }

    @Test("installs and builds are medium")
    func medium() {
        #expect(RiskScorer.score(command: "npm install") == .medium)
        #expect(RiskScorer.score(command: "git commit -m wip") == .medium)
    }

    @Test("sudo and destructive deletes are high")
    func high() {
        #expect(RiskScorer.score(command: "sudo apt remove foo") == .high)
        #expect(RiskScorer.score(command: "rm -rf node_modules") == .high)
    }

    @Test("force-push main and rm -rf / are critical")
    func critical() {
        #expect(RiskScorer.score(command: "git push --force origin main") == .critical)
        #expect(RiskScorer.score(command: "rm -rf /") == .critical)
    }
}
