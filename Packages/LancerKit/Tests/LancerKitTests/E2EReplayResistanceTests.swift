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
        let (seq, gen, unwrapped) = try SeqFrame.unwrap(wrapped)
        #expect(seq == 7)
        #expect(gen == "", "omitting gen must round-trip as an empty string, matching the Go daemon's omitempty")
        let originalObj = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let roundTrippedObj = try JSONSerialization.jsonObject(with: unwrapped) as? [String: Any]
        #expect(originalObj?["type"] as? String == roundTrippedObj?["type"] as? String)
    }

    @Test("SeqFrame wrap/unwrap round-trips a non-empty generation tag")
    func seqFrameGenRoundTrip() throws {
        let body = Data(#"{"type":"approval","payload":{}}"#.utf8)
        let wrapped = try SeqFrame.wrap(seq: 3, gen: "gen-xyz", body: body)
        let (seq, gen, _) = try SeqFrame.unwrap(wrapped)
        #expect(seq == 3)
        #expect(gen == "gen-xyz")
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
        let (firstSeq, _, _) = try SeqFrame.unwrap(firstPlaintext)
        #expect(receiver.accept(firstSeq) == true)

        // Replay of the IDENTICAL captured frame: AEAD still opens it (it has no
        // memory of prior deliveries), but the sequencer must reject it.
        let replayedPlaintext = try PairingCrypto.decrypt(frame, using: key)
        let (replaySeq, _, _) = try SeqFrame.unwrap(replayedPlaintext)
        #expect(receiver.accept(replaySeq) == false, "a replayed frame must be rejected, not accepted a second time")
    }

    @Test("peer re-key resets receive sequence space so seq=0 is accepted again")
    @MainActor
    func peerRekeyResetsReceiveSequenceSpace() {
        let client = E2ERelayClient(
            relayURL: URL(string: "https://relay.example.com")!,
            pairingCode: "111222"
        )

        let peerA = PairingCrypto.generateKeyPair()
        client.simulateIncomingFrameForTesting(#"{"type":"peer_joined","peerPublicKey":"\#(peerA.publicKeyBase64URL)"}"#)
        #expect(client.pairingState == .paired)

        #expect(client.acceptIncomingSequenceForTesting(5) == true)
        #expect(client.acceptIncomingSequenceForTesting(0) == false)
        client.setSendSequenceForTesting(7)

        let peerB = PairingCrypto.generateKeyPair()
        client.simulateIncomingFrameForTesting(#"{"type":"peer_joined","peerPublicKey":"\#(peerB.publicKeyBase64URL)"}"#)
        #expect(client.pairingState == .paired)
        #expect(client.acceptIncomingSequenceForTesting(0) == true)
        #expect(client.sendSequenceForTesting == 0)
    }

    @Test("invalid peer re-key preserves the active replay window")
    @MainActor
    func invalidPeerRekeyPreservesReplayWindow() {
        let client = E2ERelayClient(
            relayURL: URL(string: "https://relay.example.com")!,
            pairingCode: "111222"
        )

        let peer = PairingCrypto.generateKeyPair()
        client.simulateIncomingFrameForTesting(#"{"type":"peer_joined","peerPublicKey":"\#(peer.publicKeyBase64URL)"}"#)
        #expect(client.pairingState == .paired)
        #expect(client.acceptIncomingSequenceForTesting(5) == true)
        client.setSendSequenceForTesting(7)

        client.simulateIncomingFrameForTesting(#"{"type":"peer_joined","peerPublicKey":"not-a-valid-key"}"#)

        #expect(client.acceptIncomingSequenceForTesting(0) == false)
        #expect(client.sendSequenceForTesting == 7)
    }

    // MARK: - Generation guard (2026-07-15 stuck-Working/Retry root-cause fix)

    // Mirrors the Go daemon's TestE2EGenerationGuardStopsCrossGenerationPoisoning
    // exactly: the live-reproduced bug is a stale in-flight frame from a
    // PREVIOUS generation arriving AFTER reset() and poisoning `last` so every
    // legitimate new-generation frame (seq starting at 0) is rejected as
    // "out of order" — on the OLD bare-counter ReplaySequencer this failed;
    // gen-tagging must reject the stale frame instead, without touching state.
    @Test("generation-tagged sequencer rejects a stale-generation frame instead of poisoning the new generation's counter")
    func generationGuardStopsCrossGenerationPoisoning() {
        let seq = ReplaySequencer()

        // Generation A: frames 100, 101 accepted normally.
        #expect(seq.accept(gen: "gen-A", seq: 100) == .accepted, "gen-A seq=100 (first frame ever) must be accepted")
        #expect(seq.accept(gen: "gen-A", seq: 101) == .accepted, "gen-A seq=101 must be accepted")

        // A re-pair fires (daemon restarted / app relaunched) — reset().
        seq.reset()

        // A stale gen-A frame (seq=102) arrives after reset(). On the OLD
        // bare-counter code this would be accepted (102 > 0) and poison
        // `last` to 102.
        #expect(seq.accept(gen: "gen-A", seq: 102) == .staleGeneration, "stale gen-A seq=102 after reset() must be rejected as staleGeneration")

        // Generation B's frames, starting at seq=0, MUST be accepted — the
        // exact assertion that fails on the old code.
        #expect(seq.accept(gen: "gen-B", seq: 0) == .accepted, "gen-B seq=0 must be accepted after a stale gen-A frame arrived")
        #expect(seq.accept(gen: "gen-B", seq: 1) == .accepted)
        #expect(seq.accept(gen: "gen-B", seq: 2) == .accepted)

        // gen-A stays retired even after gen-B is current.
        #expect(seq.accept(gen: "gen-A", seq: 103) == .staleGeneration)

        // True replay WITHIN gen-B must still be rejected.
        #expect(seq.accept(gen: "gen-B", seq: 1) == .replayed)
        #expect(seq.accept(gen: "gen-B", seq: 0) == .replayed)
    }

    // A not-yet-upgraded peer (gen == "" on every frame) must see byte-for-byte
    // the same accept/reject decisions as the original bare monotonic counter,
    // including across reset() — co-deploy closes the security hole, but this
    // guards the window before both sides have upgraded.
    @Test("generation guard is a no-op for a legacy peer that never tags a generation")
    func generationGuardLegacyPeerUnchanged() {
        let seq = ReplaySequencer()

        #expect(seq.accept(gen: "", seq: 0) == .accepted)
        #expect(seq.accept(gen: "", seq: 0) == .replayed)
        #expect(seq.accept(gen: "", seq: 1) == .accepted)
        #expect(seq.accept(gen: "", seq: 1) == .replayed)
        #expect(seq.accept(gen: "", seq: 0) == .replayed)

        seq.reset()
        #expect(seq.accept(gen: "", seq: 0) == .accepted, "after reset(), legacy seq=0 must be acceptable again")
        #expect(seq.accept(gen: "", seq: 1) == .accepted)
    }

    // seenGens is bounded: once more than maxTrackedGenerations distinct
    // generations have been retired, the oldest is evicted (FIFO).
    @Test("seenGens evicts the oldest retired generation once its cap is exceeded")
    func generationGuardSeenGensCapEviction() {
        let seq = ReplaySequencer()
        let maxTracked = 32

        #expect(seq.accept(gen: "gen-0", seq: 0) == .accepted)
        for i in 1...(maxTracked + 1) {
            #expect(seq.accept(gen: "gen-\(i)", seq: 0) == .accepted, "first frame of gen-\(i) must be accepted")
        }

        // Check gen-1 (still within the cap) BEFORE gen-0: a stale rejection
        // doesn't mutate state, but the gen-0 check below (looks brand-new)
        // does adopt-and-evict, so order matters for this assertion.
        #expect(seq.accept(gen: "gen-1", seq: 999) == .staleGeneration, "gen-1 should still be tracked in seenGens")
        #expect(seq.accept(gen: "gen-0", seq: 999) != .staleGeneration, "gen-0 should have been evicted (FIFO) once the cap was exceeded")
    }

    // Proves the CLIENT wires generation tagging through the real send/receive
    // plumbing, not just the standalone ReplaySequencer: sendGen must change on
    // every peer_joined, and the client's own `recv` must reject a stale-gen
    // frame from a prior pairing without poisoning the new one.
    @Test("client mints a fresh send generation on every peer_joined, and its recv rejects stale-generation frames")
    @MainActor
    func clientGenerationGuardEndToEnd() {
        let client = E2ERelayClient(
            relayURL: URL(string: "https://relay.example.com")!,
            pairingCode: "111222"
        )

        let peerA = PairingCrypto.generateKeyPair()
        client.simulateIncomingFrameForTesting(#"{"type":"peer_joined","peerPublicKey":"\#(peerA.publicKeyBase64URL)"}"#)
        #expect(client.pairingState == .paired)
        let genAfterFirstPair = client.sendGenerationForTesting
        #expect(genAfterFirstPair.isEmpty == false, "peer_joined must mint a non-empty send generation")

        #expect(client.acceptIncomingSequenceForTesting(100, gen: "gen-A") == true)
        #expect(client.acceptIncomingSequenceForTesting(101, gen: "gen-A") == true)

        // Re-pair (second peer_joined) — mints a NEW send generation and
        // resets recv, exactly like a daemon restart / app relaunch.
        let peerB = PairingCrypto.generateKeyPair()
        client.simulateIncomingFrameForTesting(#"{"type":"peer_joined","peerPublicKey":"\#(peerB.publicKeyBase64URL)"}"#)
        #expect(client.pairingState == .paired)
        let genAfterSecondPair = client.sendGenerationForTesting
        #expect(genAfterSecondPair.isEmpty == false)
        #expect(genAfterSecondPair != genAfterFirstPair, "each peer_joined must mint a DIFFERENT send generation")

        // A stale gen-A frame delivered after the re-pair must be rejected
        // without poisoning gen-B's counter.
        #expect(client.acceptIncomingSequenceForTesting(102, gen: "gen-A") == false, "stale gen-A frame after re-pair must be rejected")

        // gen-B's frames, starting at seq=0, must still be accepted.
        #expect(client.acceptIncomingSequenceForTesting(0, gen: "gen-B") == true, "gen-B seq=0 must be accepted despite the stale gen-A frame arriving first")
        #expect(client.acceptIncomingSequenceForTesting(1, gen: "gen-B") == true)
    }
}
