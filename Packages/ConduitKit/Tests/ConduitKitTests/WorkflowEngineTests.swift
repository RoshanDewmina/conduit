import Testing
@testable import AgentKit
import ConduitCore

// Thread-safe command collector used by tests that capture into @Sendable closures.
private actor CommandLog {
    private(set) var commands: [String] = []
    func append(_ command: String) { commands.append(command) }
}

private actor Counter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}

@Suite("WorkflowEngine")
struct WorkflowEngineTests {

    @Test("single-line workflow runs without param resolution")
    func singleCommand() async throws {
        let engine = WorkflowEngine()
        let log = CommandLog()
        let snippet = Snippet(id: SnippetID(), name: "test", body: "echo hello")
        try await engine.run(
            workflow: snippet,
            parameterResolver: { _ in "" },
            onCommand: { cmd in await log.append(cmd) }
        )
        #expect(await log.commands == ["echo hello"])
    }

    @Test("workflow with parameter substitutes correctly")
    func paramSubstitution() async throws {
        let engine = WorkflowEngine()
        let log = CommandLog()
        let snippet = Snippet(name: "greet", body: "echo {{greeting}}")
        try await engine.run(
            workflow: snippet,
            parameterResolver: { param in
                if param == "greeting" { return "Hello World" }
                return ""
            },
            onCommand: { cmd in await log.append(cmd) }
        )
        #expect(await log.commands == ["echo Hello World"])
    }

    @Test("multi-step workflow emits commands in order")
    func multiStep() async throws {
        let engine = WorkflowEngine()
        let log = CommandLog()
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
            onCommand: { cmd in await log.append(cmd) }
        )
        let cmds = await log.commands
        #expect(cmds.count == 2)
        #expect(cmds[0] == "git push origin main")
        #expect(cmds[1] == #"ssh prod "cd /app && git pull && systemctl restart myapp""#)
    }

    @Test("blank lines in workflow body are skipped")
    func blankLinesSkipped() async throws {
        let engine = WorkflowEngine()
        let log = CommandLog()
        let snippet = Snippet(name: "spaced", body: "cmd1\n\ncmd2\n\n")
        try await engine.run(
            workflow: snippet,
            parameterResolver: { _ in "" },
            onCommand: { cmd in await log.append(cmd) }
        )
        #expect(await log.commands == ["cmd1", "cmd2"])
    }

    @Test("same parameter in multiple lines resolved once")
    func sameParamMultipleLines() async throws {
        let engine = WorkflowEngine()
        let log = CommandLog()
        let resolverCallCount = Counter()
        let snippet = Snippet(name: "multi", body: "echo {{name}}\ngreet {{name}}")
        try await engine.run(
            workflow: snippet,
            parameterResolver: { _ in
                await resolverCallCount.increment()
                return "Alice"
            },
            onCommand: { cmd in await log.append(cmd) }
        )
        #expect(await resolverCallCount.value == 1)
        #expect(await log.commands == ["echo Alice", "greet Alice"])
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
