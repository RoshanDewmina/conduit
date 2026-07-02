import Testing
import Foundation
@testable import LancerCore

@Suite("LancerDProtocol")
struct LancerDProtocolTests {
    @Test("approval pending round-trip decode")
    func approvalPendingDecode() throws {
        let json = """
        {"jsonrpc":"2.0","method":"agent.approval.pending","params":{"id":"00000000-0000-0000-0000-000000000001","agent":"claudeCode","kind":"command","command":"rm -rf /","cwd":"/home/user","risk":3}}
        """.data(using: .utf8)!
        let event = DaemonEvent.decode(from: json)
        if case .approvalPending(let p) = event {
            #expect(p.command == "rm -rf /")
            #expect(p.risk == 3)
            #expect(p.approvalRisk == .critical)
        } else {
            Issue.record("Expected .approvalPending")
        }
    }

    @Test("approval pending decode carries the daemon's contentHash")
    func approvalPendingDecodeContentHash() throws {
        let json = """
        {"jsonrpc":"2.0","method":"agent.approval.pending","params":{"id":"00000000-0000-0000-0000-000000000001","agent":"claudeCode","kind":"command","command":"rm -rf /","cwd":"/home/user","risk":3,"contentHash":"c5fca73ef15566810d568ca87f42cf1d917e78ce9c51d9b641a6d783c4c5c7b3"}}
        """.data(using: .utf8)!
        let event = DaemonEvent.decode(from: json)
        if case .approvalPending(let p) = event {
            #expect(p.contentHash == "c5fca73ef15566810d568ca87f42cf1d917e78ce9c51d9b641a6d783c4c5c7b3")
            #expect(p.approvalContentHash == p.contentHash)
        } else {
            Issue.record("Expected .approvalPending")
        }
    }

    @Test("approval pending decode tolerates a missing contentHash (legacy daemon)")
    func approvalPendingDecodeMissingContentHash() throws {
        let json = """
        {"jsonrpc":"2.0","method":"agent.approval.pending","params":{"id":"00000000-0000-0000-0000-000000000001","agent":"claudeCode","kind":"command","command":"rm -rf /","cwd":"/home/user","risk":3}}
        """.data(using: .utf8)!
        let event = DaemonEvent.decode(from: json)
        if case .approvalPending(let p) = event {
            #expect(p.contentHash == nil)
        } else {
            Issue.record("Expected .approvalPending")
        }
    }

    @Test("unknown method returns unknown event")
    func unknownMethod() {
        let json = """
        {"jsonrpc":"2.0","method":"session.attach","params":{}}
        """.data(using: .utf8)!
        if case .unknown(let method) = DaemonEvent.decode(from: json) {
            #expect(method == "session.attach")
        } else {
            Issue.record("Expected .unknown")
        }
    }

    @Test("framing round-trip")
    func framingRoundTrip() {
        let payload = Data("hello".utf8)
        let framed = DaemonFraming.frame(payload)
        #expect(framed.count == 4 + payload.count)
        if let (unframed, rest) = DaemonFraming.unframe(framed) {
            #expect(unframed == payload)
            #expect(rest.isEmpty)
        } else {
            Issue.record("unframe returned nil")
        }
    }

    @Test("unframe returns nil when incomplete")
    func incompleteFrame() {
        let data = Data([0, 0, 0, 10, 1, 2])  // says 10 bytes but only 2 available
        #expect(DaemonFraming.unframe(data) == nil)
    }

    @Test("multi-frame parsing")
    func multiFrame() {
        let msg1 = Data("first".utf8)
        let msg2 = Data("second".utf8)
        var buf = DaemonFraming.frame(msg1)
        buf.append(DaemonFraming.frame(msg2))

        let (m1, rest1) = DaemonFraming.unframe(buf)!
        #expect(m1 == msg1)
        let (m2, rest2) = DaemonFraming.unframe(rest1)!
        #expect(m2 == msg2)
        #expect(rest2.isEmpty)
    }
}
