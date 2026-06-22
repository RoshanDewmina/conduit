import XCTest
@testable import LancerCore

final class SessionDiscoveryDecodeTests: XCTestCase {
    func testSessionDefaultOriginIsAppInitiated() {
        let s = Session(hostID: HostID())
        XCTAssertEqual(s.origin, .appInitiated)
    }

    func testDecodeSessionDiscovered() {
        let json = #"{"jsonrpc":"2.0","method":"session.discovered","params":{"sessionId":"abc123","tmuxName":"lancer-abc123","agent":"claudeCode","cwd":"/tmp","managed":true}}"#
        let data = Data(json.utf8)
        guard let event = DaemonEvent.decode(from: data) else {
            return XCTFail("decode returned nil")
        }
        guard case let .sessionDiscovered(p) = event else {
            return XCTFail("wrong case")
        }
        XCTAssertEqual(p.sessionId, "abc123")
        XCTAssertEqual(p.tmuxName, "lancer-abc123")
        XCTAssertEqual(p.agent, "claudeCode")
        XCTAssertTrue(p.managed)
    }
}
