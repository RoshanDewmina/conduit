import Foundation
import Testing
@testable import AgentKit

@Suite("AgentRegistry")
struct AgentRegistryTests {

    @Test("defaults contain Claude, Codex, OpenCode, Cursor, Grok, Pi, Gemini")
    func defaultsContainBuiltInAgents() {
        let registry = AgentRegistry.defaults
        let ids = Set(registry.registrations.map(\.id))
        #expect(ids.contains(AgentKind.claude.rawValue))
        #expect(ids.contains(AgentKind.codex.rawValue))
        #expect(ids.contains(AgentKind.opencode.rawValue))
        #expect(ids.contains(AgentKind.cursor.rawValue))
        #expect(ids.contains(AgentKind.grok.rawValue))
        #expect(ids.contains(AgentKind.pi.rawValue))
        #expect(ids.contains(AgentKind.gemini.rawValue))
    }

    @Test("Cursor registration resumes with --resume and print mode")
    func cursorResumeCommand() {
        let cursor = AgentRegistry.defaults.registration(id: AgentKind.cursor.rawValue)
        #expect(cursor?.name == "Cursor")
        #expect(cursor?.resumeCommand.contains("--resume {{sessionId}}") == true)
        #expect(cursor?.resumeCommand.contains("-p") == true)
        #expect(cursor?.resumeCommand.contains("--trust") == true)
        if case .argvOption(let flag) = cursor?.sessionIdSource {
            #expect(flag == "--resume")
        } else {
            Issue.record("expected argvOption --resume")
        }
    }

    @Test("OpenCode registration resumes with --session")
    func opencodeResumeCommand() {
        let opencode = AgentRegistry.defaults.registration(id: AgentKind.opencode.rawValue)
        #expect(opencode?.name == "OpenCode")
        #expect(opencode?.resumeCommand.contains("--session {{sessionId}}") == true)
        if case .argvOption(let flag) = opencode?.sessionIdSource {
            #expect(flag == "--session")
        } else {
            Issue.record("expected argvOption --session")
        }
    }

    @Test("registration(id:) returns the right agent")
    func lookupByID() {
        let registry = AgentRegistry.defaults
        let claude = registry.registration(id: "claude")
        #expect(claude?.name == "Claude Code")
        #expect(claude?.resumeCommand.contains("{{sessionId}}") == true)
    }

    @Test("duplicate IDs collapse, later wins")
    func deduplicatesPreservingLastValue() {
        let first = AgentRegistration(
            id: "custom-x",
            name: "First",
            detect: AgentDetectRule(processName: "x"),
            sessionIdSource: .argvOption("--id"),
            resumeCommand: "x --id {{sessionId}}"
        )
        let second = AgentRegistration(
            id: "custom-x",
            name: "Second",
            detect: AgentDetectRule(processName: "x"),
            sessionIdSource: .argvOption("--id"),
            resumeCommand: "x --id {{sessionId}}"
        )
        let registry = AgentRegistry(registrations: [first, second])
        #expect(registry.registrations.count == 1)
        #expect(registry.registration(id: "custom-x")?.name == "Second")
    }

    @Test("invalid IDs and reserved IDs fail to decode")
    func decoderRejectsInvalidAndReservedIDs() throws {
        // Reserved (built-in AgentKind) — should fail
        let reservedJSON = """
        {"id":"claude","name":"x","detect":{},"sessionIdSource":"--resume","resumeCommand":"x {{sessionId}}"}
        """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(AgentRegistration.self, from: reservedJSON)
        }

        // Invalid characters in ID
        let badJSON = """
        {"id":"has space","name":"x","detect":{},"sessionIdSource":"--resume","resumeCommand":"x {{sessionId}}"}
        """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(AgentRegistration.self, from: badJSON)
        }
    }

    @Test("resumeCommand without sessionId placeholder fails to decode")
    func decoderRejectsMissingPlaceholder() {
        let badJSON = """
        {"id":"myagent","name":"x","detect":{},"sessionIdSource":"--resume","resumeCommand":"x --no-placeholder"}
        """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(AgentRegistration.self, from: badJSON)
        }
    }

    @Test("sessionIdSource accepts string and object forms")
    func sessionIDSourceDecodesBothForms() throws {
        let stringForm = """
        "--resume"
        """.data(using: .utf8)!
        let source1 = try JSONDecoder().decode(AgentSessionIDSource.self, from: stringForm)
        if case .argvOption(let opt) = source1 {
            #expect(opt == "--resume")
        } else {
            Issue.record("Expected .argvOption")
        }

        let objectForm = """
        {"type":"argvOption","argvOption":"--session"}
        """.data(using: .utf8)!
        let source2 = try JSONDecoder().decode(AgentSessionIDSource.self, from: objectForm)
        if case .argvOption(let opt) = source2 {
            #expect(opt == "--session")
        } else {
            Issue.record("Expected .argvOption")
        }

        let piForm = """
        "piSessionFile"
        """.data(using: .utf8)!
        let source3 = try JSONDecoder().decode(AgentSessionIDSource.self, from: piForm)
        #expect(source3 == .piSessionFile)
    }
}
