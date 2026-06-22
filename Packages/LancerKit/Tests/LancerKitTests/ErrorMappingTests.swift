import Testing
import Foundation
@testable import SSHTransport
@testable import LancerCore
@preconcurrency import Citadel

// MARK: - B4: SSHSession error mapping (A4)

@Suite("SSHSession — type-based error mapping")
struct ErrorMappingTests {

    // MARK: - Citadel type-based catches

    @Test("SSHClientError.allAuthenticationOptionsFailed maps to .authFailed")
    func allAuthOptionsFailed() {
        let mapped = SSHSession.map(error: SSHClientError.allAuthenticationOptionsFailed, host: "h")
        if case .authFailed = mapped { } else {
            Issue.record("Expected .authFailed, got \(mapped)")
        }
    }

    @Test("SSHClientError.channelCreationFailed maps to .channelClosed")
    func sshClientChannelCreation() {
        let mapped = SSHSession.map(error: SSHClientError.channelCreationFailed, host: "h")
        #expect(mapped == .channelClosed)
    }

    @Test("CitadelError.unauthorized maps to .authFailed")
    func citadelUnauthorized() {
        let mapped = SSHSession.map(error: CitadelError.unauthorized, host: "h")
        if case .authFailed = mapped { } else {
            Issue.record("Expected .authFailed, got \(mapped)")
        }
    }

    @Test("CitadelError.channelFailure maps to .channelClosed")
    func citadelChannelFailure() {
        #expect(SSHSession.map(error: CitadelError.channelFailure, host: "h") == .channelClosed)
    }

    @Test("CitadelError.channelCreationFailed maps to .channelClosed")
    func citadelChannelCreationFailed() {
        #expect(SSHSession.map(error: CitadelError.channelCreationFailed, host: "h") == .channelClosed)
    }

    // MARK: - LancerError pass-through

    @Test("LancerError.timeout passes through unchanged")
    func lancerErrorPassthrough() {
        #expect(SSHSession.map(error: LancerError.timeout, host: "h") == .timeout)
    }

    @Test("LancerError.notConnected passes through unchanged")
    func lancerNotConnectedPassthrough() {
        #expect(SSHSession.map(error: LancerError.notConnected, host: "h") == .notConnected)
    }

    // MARK: - String-based fallbacks (for OS-level errors without Citadel types)

    @Test("'connection refused' string maps to .connectionRefused")
    func connectionRefusedString() {
        struct RefusedError: Error, CustomStringConvertible {
            var description: String { "connection refused to 10.0.0.1:22" }
        }
        let mapped = SSHSession.map(error: RefusedError(), host: "10.0.0.1")
        if case .connectionRefused(let host) = mapped {
            #expect(host == "10.0.0.1")
        } else {
            Issue.record("Expected .connectionRefused, got \(mapped)")
        }
    }

    @Test("'timed out' string maps to .timeout")
    func timedOutString() {
        struct TimeoutError: Error, CustomStringConvertible {
            var description: String { "operation timed out after 15s" }
        }
        let mapped = SSHSession.map(error: TimeoutError(), host: "h")
        #expect(mapped == .timeout)
    }

    @Test("unknown error maps to .unknown")
    func unknownErrorFallback() {
        struct WeirdError: Error {}
        let mapped = SSHSession.map(error: WeirdError(), host: "h")
        if case .unknown = mapped { } else {
            Issue.record("Expected .unknown, got \(mapped)")
        }
    }

    @Test("type-based match takes priority over string fallback for Citadel errors")
    func typeBeatsString() {
        // CitadelError.unauthorized should map via type, not via string inspection
        let mapped = SSHSession.map(error: CitadelError.unauthorized, host: "h")
        if case .authFailed = mapped { } else {
            Issue.record("Type-based mapping for CitadelError.unauthorized failed: \(mapped)")
        }
    }
}
