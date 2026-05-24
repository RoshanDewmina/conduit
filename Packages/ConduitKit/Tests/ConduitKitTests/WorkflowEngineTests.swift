import Testing
@testable import AgentKit
import ConduitCore

@Suite("WorkflowEngine")
struct WorkflowEngineTests {

    @Test("single-line workflow runs without param resolution")
    func singleCommand() async throws {
        let engine = WorkflowEngine()
        var commands: [String] = []
        let snippet = Snippet(id: SnippetID(), name: "test", body: "echo hello")
        try await engine.run(
            workflow: snippet,
            parameterResolver: { _ in "" },
            onCommand: { commands.append($0) }
        )
        #expect(commands == ["echo hello"])
    }

    @Test("workflow with parameter substitutes correctly")
    func paramSubstitution() async throws {
        let engine = WorkflowEngine()
        var commands: [String] = []
        let snippet = Snippet(name: "greet", body: "echo {{greeting}}")
        try await engine.run(
            workflow: snippet,
            parameterResolver: { param in
                if param == "greeting" { return "Hello World" }
                return ""
            },
            onCommand: { commands.append($0) }
        )
        #expect(commands == ["echo Hello World"])
    }

    @Test("multi-step workflow emits commands in order")
    func multiStep() async throws {
        let engine = WorkflowEngine()
        var commands: [String] = []
        let body = """
        git push origin {{branch}}
        ssh prod "cd /app && git pull && systemctl restart myapp"
        """
        let snippet = Snippet(name: "deploy", body: body)
        try await engine.run(
            workflow: snippet,
            parameterResolver: { param in
                if param == "branch" { return "main" }
                return ""
            },
            onCommand: { commands.append($0) }
        )
        #expect(commands.count == 2)
        #expect(commands[0] == "git push origin main")
        #expect(commands[1] == #"ssh prod "cd /app && git pull && systemctl restart myapp""#)
    }

    @Test("blank lines in workflow body are skipped")
    func blankLinesSkipped() async throws {
        let engine = WorkflowEngine()
        var commands: [String] = []
        let snippet = Snippet(name: "spaced", body: "cmd1\n\ncmd2\n\n")
        try await engine.run(
            workflow: snippet,
            parameterResolver: { _ in "" },
            onCommand: { commands.append($0) }
        )
        #expect(commands == ["cmd1", "cmd2"])
    }

    @Test("same parameter in multiple lines resolved once")
    func sameParamMultipleLines() async throws {
        let engine = WorkflowEngine()
        var commands: [String] = []
        var resolverCallCount = 0
        let snippet = Snippet(name: "multi", body: "echo {{name}}\ngreet {{name}}")
        try await engine.run(
            workflow: snippet,
            parameterResolver: { param in
                resolverCallCount += 1
                return "Alice"
            },
            onCommand: { commands.append($0) }
        )
        #expect(resolverCallCount == 1)
        #expect(commands == ["echo Alice", "greet Alice"])
    }

    @Test("extractParams returns unique params in order")
    func extractParamsOrder() async throws {
        let engine = WorkflowEngine()
        let params = await engine.extractParams(from: "{{a}} and {{b}} and {{a}} again")
        #expect(params == ["a", "b"])
    }

    @Test("extractParams returns empty for line without params")
    func extractParamsEmpty() async throws {
        let engine = WorkflowEngine()
        let params = await engine.extractParams(from: "echo hello world")
        #expect(params.isEmpty)
    }
}
