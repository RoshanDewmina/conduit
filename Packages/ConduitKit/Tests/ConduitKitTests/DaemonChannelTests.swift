import Testing
import Foundation
@testable import SSHTransport
import ConduitCore

@Suite("DaemonChannel framing")
struct DaemonChannelTests {
    @Test("single framed event is decoded correctly")
    func singleEvent() async throws {
        let json = """
        {"jsonrpc":"2.0","method":"agent.approval.pending","params":{"id":"00000000-0000-0000-0000-000000000001","agent":"claudeCode","kind":"command","command":"ls","cwd":"/","risk":0}}
        """.data(using: .utf8)!
        let framed = DaemonFraming.frame(json)
        // Use DaemonFraming directly to verify (channel wiring requires a live session)
        let result = DaemonFraming.unframe(framed)
        #expect(result != nil)
        if let (msg, _) = result {
            let event = DaemonEvent.decode(from: msg)
            if case .approvalPending(let p) = event {
                #expect(p.command == "ls")
            } else {
                Issue.record("Expected approvalPending")
            }
        }
    }

    @Test("partial frame waits for more bytes")
    func partialFrame() {
        let json = Data("hello world this is a test message".utf8)
        let framed = DaemonFraming.frame(json)
        let partial = framed.prefix(framed.count - 2)
        #expect(DaemonFraming.unframe(Data(partial)) == nil)
    }
}
