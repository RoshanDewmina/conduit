import XCTest
@testable import AppFeature

final class EditToolDiffParserTests: XCTestCase {
    func testParsesEditOldAndNewStrings() {
        let json = """
        {"file_path":"Packages/LancerKit/Sources/Foo.swift","old_string":"let a = 1\\nlet b = 2","new_string":"let a = 1\\nlet b = 3\\nlet c = 4"}
        """
        let presentation = EditToolDiffParser.parse(toolName: "Edit", inputJSON: json)
        XCTAssertNotNil(presentation)
        XCTAssertEqual(presentation?.fileName, "Foo.swift")
        XCTAssertEqual(presentation?.navigationTitle, "Edit")
        XCTAssertEqual(presentation?.segments.count, 1)
        XCTAssertEqual(presentation?.totalRemoved, 2)
        XCTAssertEqual(presentation?.totalAdded, 3)
        XCTAssertEqual(presentation?.segments.first?.deletions.map(\.text), ["let a = 1", "let b = 2"])
        XCTAssertEqual(presentation?.segments.first?.additions.map(\.text), ["let a = 1", "let b = 3", "let c = 4"])
        XCTAssertEqual(presentation?.segments.first?.deletions.first?.kind, .del)
        XCTAssertEqual(presentation?.segments.first?.additions.first?.kind, .add)
    }

    func testParsesWriteContentAsAdditionsOnly() {
        let json = """
        {"file_path":"/tmp/hello.txt","content":"hello\\nworld"}
        """
        let presentation = EditToolDiffParser.parse(toolName: "Write", inputJSON: json)
        XCTAssertEqual(presentation?.navigationTitle, "Write")
        XCTAssertEqual(presentation?.totalRemoved, 0)
        XCTAssertEqual(presentation?.totalAdded, 2)
        XCTAssertTrue(presentation?.segments.first?.deletions.isEmpty == true)
    }

    func testParsesMultiEditSegments() {
        let json = """
        {"file_path":"A.swift","edits":[{"old_string":"one","new_string":"ONE"},{"old_string":"two\\nlines","new_string":"TWO"}]}
        """
        let presentation = EditToolDiffParser.parse(toolName: "MultiEdit", inputJSON: json)
        XCTAssertEqual(presentation?.segments.count, 2)
        XCTAssertEqual(presentation?.segments[0].title, "Edit 1")
        XCTAssertEqual(presentation?.segments[1].removedCount, 2)
        XCTAssertEqual(presentation?.totalAdded, 2)
    }

    func testUnwrapsNestedInputPayload() {
        let json = """
        {"name":"Edit","input":{"file_path":"Nested.swift","old_string":"a","new_string":"b"}}
        """
        let presentation = EditToolDiffParser.parse(toolName: "Edit", inputJSON: json)
        XCTAssertEqual(presentation?.fileName, "Nested.swift")
        XCTAssertEqual(presentation?.totalAdded, 1)
        XCTAssertEqual(presentation?.totalRemoved, 1)
    }

    func testSupportsDiffSheetNames() {
        XCTAssertTrue(EditToolDiffParser.supportsDiffSheet(toolName: "Edit"))
        XCTAssertTrue(EditToolDiffParser.supportsDiffSheet(toolName: "write"))
        XCTAssertTrue(EditToolDiffParser.supportsDiffSheet(toolName: "MultiEdit"))
        XCTAssertFalse(EditToolDiffParser.supportsDiffSheet(toolName: "Bash"))
        XCTAssertFalse(EditToolDiffParser.supportsDiffSheet(toolName: "Read"))
    }

    func testReturnsNilForNonEditToolsAndEmptyPayloads() {
        XCTAssertNil(EditToolDiffParser.parse(toolName: "Bash", inputJSON: #"{"command":"ls"}"#))
        XCTAssertNil(EditToolDiffParser.parse(toolName: "Edit", inputJSON: #"{"file_path":"x.swift"}"#))
        XCTAssertNil(EditToolDiffParser.parse(toolName: "Edit", inputJSON: nil))
    }
}
