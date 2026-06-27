import Testing
import Foundation
@testable import HostControlKit

@Suite struct VerificationPhraseTests {
    @Test func isDeterministic() {
        let key = "MCowBQYDK2VwAyEAabcdef0123456789"
        #expect(VerificationPhrase.make(fromPublicKey: key) == VerificationPhrase.make(fromPublicKey: key))
    }

    @Test func differentKeysDifferentPhrases() {
        let a = VerificationPhrase.make(fromPublicKey: "keyAAAA")
        let b = VerificationPhrase.make(fromPublicKey: "keyBBBB")
        #expect(a != b)
    }

    @Test func defaultIsFourWordsFromTheList() {
        let phrase = VerificationPhrase.make(fromPublicKey: "anything")
        let words = phrase.split(separator: "-").map(String.init)
        #expect(words.count == 4)
        for w in words { #expect(VerificationPhrase.wordlist.contains(w)) }
    }

    @Test func wordCountIsHonoredEvenBeyondDigestLength() {
        let phrase = VerificationPhrase.make(fromPublicKey: "x", wordCount: 40)
        #expect(phrase.split(separator: "-").count == 40)
    }

    @Test func wordlistHasExactlySixtyFourEntries() {
        // 6 bits per word indexes 0..63 — the list must be exactly 64 long or
        // some indices would crash / never appear.
        #expect(VerificationPhrase.wordlist.count == 64)
    }
}
