import Foundation
import Testing
@testable import ConduitCore
@testable import PersistenceKit
@testable import AppFeature

@Suite("ChatArtifactRendering")
struct ChatArtifactRenderingTests {

    // MARK: - Kind raw values

    @Test("ChatArtifact.Kind raw values round-trip")
    func kindRawValues() {
        for kind in [ChatArtifact.Kind.tool, .diff, .file, .test, .preview, .approval] {
            #expect(ChatArtifact.Kind(rawValue: kind.rawValue) == kind)
        }
    }

    @Test("ChatArtifact.Kind unknown raw value returns nil")
    func kindUnknownRawValue() {
        #expect(ChatArtifact.Kind(rawValue: "unknown") == nil)
    }

    // MARK: - Status raw values

    @Test("ChatArtifact.Status raw values round-trip")
    func statusRawValues() {
        for status in [ChatArtifact.Status.running, .done, .failed] {
            #expect(ChatArtifact.Status(rawValue: status.rawValue) == status)
        }
    }

    @Test("ChatArtifact.Status unknown raw value returns nil")
    func statusUnknownRawValue() {
        #expect(ChatArtifact.Status(rawValue: "pending") == nil)
    }

    // MARK: - Artifact initialization

    @Test("ChatArtifact default init produces valid artifact")
    func defaultInit() {
        let artifact = ChatArtifact(
            conversationID: "conv-1",
            turnID: "turn-1",
            runID: "run-1",
            kind: .tool,
            title: "bash"
        )
        #expect(artifact.conversationID == "conv-1")
        #expect(artifact.turnID == "turn-1")
        #expect(artifact.runID == "run-1")
        #expect(artifact.kind == .tool)
        #expect(artifact.title == "bash")
        #expect(artifact.summary == nil)
        #expect(artifact.payloadJSON == "{}")
        #expect(artifact.status == .running)
    }

    @Test("ChatArtifact with all fields")
    func fullInit() {
        let now = Date()
        let artifact = ChatArtifact(
            id: "art-1",
            conversationID: "conv-1",
            turnID: "turn-1",
            runID: "run-1",
            kind: .diff,
            title: "edit main.swift",
            summary: "+5 -2",
            payloadJSON: "{\"diff\": \"+added\\n-removed\"}",
            status: .done,
            createdAt: now,
            updatedAt: now
        )
        #expect(artifact.id == "art-1")
        #expect(artifact.kind == .diff)
        #expect(artifact.summary == "+5 -2")
        #expect(artifact.status == .done)
        #expect(artifact.createdAt == now)
    }

    // MARK: - Payload JSON parsing helpers

    @Test("Tool payload with command key extracts command")
    func toolPayloadCommand() throws {
        let json = "{\"command\": \"ls -la\"}"
        let data = json.data(using: .utf8)!
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["command"] as? String == "ls -la")
    }

    @Test("Tool payload with path key extracts path")
    func toolPayloadPath() throws {
        let json = "{\"path\": \"/tmp/test.txt\"}"
        let data = json.data(using: .utf8)!
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["path"] as? String == "/tmp/test.txt")
    }

    @Test("Diff payload with insertions/deletions")
    func diffPayloadStats() throws {
        let json = "{\"insertions\": 12, \"deletions\": 3}"
        let data = json.data(using: .utf8)!
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["insertions"] as? Int == 12)
        #expect(obj?["deletions"] as? Int == 3)
    }

    @Test("Preview payload with url")
    func previewPayloadURL() throws {
        let json = "{\"url\": \"http://localhost:3000\"}"
        let data = json.data(using: .utf8)!
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["url"] as? String == "http://localhost:3000")
    }

    @Test("Test payload with output")
    func testPayloadOutput() throws {
        let json = "{\"output\": \"3 passed, 0 failed\"}"
        let data = json.data(using: .utf8)!
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["output"] as? String == "3 passed, 0 failed")
    }

    @Test("Empty payload JSON parses to empty dict")
    func emptyPayload() throws {
        let data = "{}".data(using: .utf8)!
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?.isEmpty == true)
    }

    // MARK: - Artifact Codable round-trip

    @Test("ChatArtifact Encodable/Decodable round-trip")
    func artifactCodable() throws {
        let artifact = ChatArtifact(
            id: "art-rt",
            conversationID: "conv-rt",
            turnID: "turn-rt",
            runID: "run-rt",
            kind: .approval,
            title: "approve deploy",
            summary: "Deploy to prod",
            payloadJSON: "{\"risk\": 3}",
            status: .running,
            createdAt: Date(timeIntervalSince1970: 1000),
            updatedAt: Date(timeIntervalSince1970: 2000)
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(artifact)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ChatArtifact.self, from: data)
        #expect(decoded.id == artifact.id)
        #expect(decoded.kind == .approval)
        #expect(decoded.status == .running)
        #expect(decoded.title == "approve deploy")
        #expect(decoded.summary == "Deploy to prod")
    }

    // MARK: - All artifact kinds are handled by ChatArtifactCard

    @Test("All six artifact kinds have valid raw values")
    func allKindsExist() {
        let allKinds: [ChatArtifact.Kind] = [.tool, .diff, .file, .test, .preview, .approval]
        #expect(allKinds.count == 6)
        for kind in allKinds {
            #expect(ChatArtifact.Kind(rawValue: kind.rawValue) != nil)
        }
    }
}
