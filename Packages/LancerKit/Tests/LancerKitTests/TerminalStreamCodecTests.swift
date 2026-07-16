#if os(iOS)
import Foundation
import Testing
@testable import SessionFeature

@Suite("TerminalStreamCodec")
struct TerminalStreamCodecTests {
    @Test("round-trips Orca binary frame header + payload")
    func roundTrip() {
        let payload = Data("ORCA_PING\n".utf8)
        let encoded = TerminalStreamCodec.encode(
            opcode: .output,
            streamId: 7,
            seq: 0x1_0000_0002,
            payload: payload
        )
        let frame = TerminalStreamCodec.decode(encoded)
        #expect(frame != nil)
        #expect(frame?.opcode == .output)
        #expect(frame?.streamId == 7)
        #expect(frame?.seq == 0x1_0000_0002)
        #expect(frame?.payload == payload)
    }
}
#endif
