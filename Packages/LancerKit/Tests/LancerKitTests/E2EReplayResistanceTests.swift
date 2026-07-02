import Testing
import Foundation
@testable import SSHTransport
@testable import SecurityKit

@Suite("E2E relay replay resistance")
struct E2EReplayResistanceTests {

    @Test("SeqFrame wrap/unwrap round-trips seq and body")
    func seqFrameRoundTrip() throws {
        let body = Data(#"{"type":"approval","payload":{"approvalID":"a-1"}}"#.utf8)
        let wrapped = try SeqFrame.wrap(seq: 7, body: body)
        let (seq, unwrapped) = try SeqFrame.unwrap(wrapped)
        #expect(seq == 7)
        let originalObj = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let roundTrippedObj = try JSONSerialization.jsonObject(with: unwrapped) as? [String: Any]
        #expect(originalObj?["type"] as? String == roundTrippedObj?["type"] as? String)
    }

    @Test("ReplaySequencer rejects a repeated or out-of-order sequence")
    func replaySequencerRejectsReplay() {
        let seq = ReplaySequencer()
        #expect(seq.accept(0) == true, "first-ever sequence must be accepted")
        #expect(seq.accept(0) == false, "replaying the same sequence must be rejected")
        #expect(seq.accept(1) == true, "a strictly higher sequence must be accepted")
        #expect(seq.accept(1) == false, "replaying seq=1 must be rejected")
        #expect(seq.accept(0) == false, "an earlier sequence must be rejected even though seq=1 was already accepted")
    }

    @Test("ReplaySequencer.reset() allows seq=0 again for a new pairing generation")
    func replaySequencerResets() {
        let seq = ReplaySequencer()
        #expect(seq.accept(0) == true)
        #expect(seq.accept(5) == true)
        seq.reset()
        #expect(seq.accept(0) == true, "after reset(), the new generation starts fresh")
    }

    // Proves the actual security property end-to-end at the crypto layer this
    // client uses: a captured frame that decrypts successfully a SECOND time
    // (AEAD alone has no notion of "already seen") must still only be accepted
    // once by the seq envelope + ReplaySequencer layered on top.
    @Test("a captured-and-replayed encrypted frame is rejected on redelivery")
    func replayedEncryptedFrameRejectedOnRedelivery() throws {
        let app = PairingCrypto.generateKeyPair()
        let helper = PairingCrypto.generateKeyPair()
        let key = try PairingCrypto.deriveSessionKey(
            privateKey: app.privateKey,
            peerPublicKeyBase64URL: helper.publicKeyBase64URL,
            helperID: "test-helper",
            helperPublicKeyBase64URL: helper.publicKeyBase64URL,
            appPublicKeyBase64URL: app.publicKeyBase64URL
        )

        let body = Data(#"{"type":"approval","payload":{}}"#.utf8)
        let wrapped = try SeqFrame.wrap(seq: 0, body: body)
        let frame = try PairingCrypto.encrypt(wrapped, using: key)

        let receiver = ReplaySequencer()

        // First delivery: decrypts fine and is accepted.
        let firstPlaintext = try PairingCrypto.decrypt(frame, using: key)
        let (firstSeq, _) = try SeqFrame.unwrap(firstPlaintext)
        #expect(receiver.accept(firstSeq) == true)

        // Replay of the IDENTICAL captured frame: AEAD still opens it (it has no
        // memory of prior deliveries), but the sequencer must reject it.
        let replayedPlaintext = try PairingCrypto.decrypt(frame, using: key)
        let (replaySeq, _) = try SeqFrame.unwrap(replayedPlaintext)
        #expect(receiver.accept(replaySeq) == false, "a replayed frame must be rejected, not accepted a second time")
    }
}
