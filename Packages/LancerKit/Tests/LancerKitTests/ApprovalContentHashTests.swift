import Testing
import Foundation
@testable import LancerCore

@Suite("Approval.computeContentHash")
struct ApprovalContentHashTests {

    @Test("deterministic for identical fields")
    func deterministic() {
        let a = Approval.computeContentHash(command: "echo hi", patch: nil, cwd: "/tmp", toolInput: nil)
        let b = Approval.computeContentHash(command: "echo hi", patch: nil, cwd: "/tmp", toolInput: nil)
        #expect(a == b)
    }

    @Test("every field participates in the digest")
    func fieldSensitive() {
        let base = Approval.computeContentHash(command: "echo hi", patch: nil, cwd: "/tmp", toolInput: nil)
        #expect(Approval.computeContentHash(command: "echo bye", patch: nil, cwd: "/tmp", toolInput: nil) != base)
        #expect(Approval.computeContentHash(command: "echo hi", patch: "diff --git a b", cwd: "/tmp", toolInput: nil) != base)
        #expect(Approval.computeContentHash(command: "echo hi", patch: nil, cwd: "/other", toolInput: nil) != base)
        #expect(Approval.computeContentHash(command: "echo hi", patch: nil, cwd: "/tmp", toolInput: "{\"x\":1}") != base)
    }

    @Test("no collision across a shifted field boundary")
    func noBoundaryCollision() {
        let a = Approval.computeContentHash(command: "ab", patch: "c", cwd: "", toolInput: nil)
        let b = Approval.computeContentHash(command: "a", patch: "bc", cwd: "", toolInput: nil)
        #expect(a != b)
    }

    // Cross-language vector: the daemon's computeContentHash (daemon/lancerd/approval.go)
    // over command="echo hi", patch="", cwd="/tmp", toolInput="" — verified by running
    // the equivalent Go call and comparing hex digests, proving both languages'
    // canonicalizations agree byte-for-byte, not just internally.
    @Test("matches the Go daemon's canonicalization for a known vector")
    func matchesGoVector() {
        let got = Approval.computeContentHash(command: "echo hi", patch: nil, cwd: "/tmp", toolInput: nil)
        #expect(got == "c5fca73ef15566810d568ca87f42cf1d917e78ce9c51d9b641a6d783c4c5c7b3")
    }
}
