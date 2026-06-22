import CryptoKit
import Foundation

/// A short, human-readable phrase derived deterministically from a host public
/// key. The Mac and the phone each render the phrase for the *same* key during
/// pairing; if the words match on both screens, the two devices agreed on the
/// same key and no machine-in-the-middle swapped it. This is a human-verifiable
/// checksum (like SSH's visual host key), not a secret — it carries no key
/// material and is safe to display.
public enum VerificationPhrase {
    /// Derives a 4-word phrase (e.g. "amber-river-quiet-stone") from a base64
    /// public key string. Deterministic: equal keys always yield equal phrases.
    public static func make(fromPublicKey publicKey: String, wordCount: Int = 4) -> String {
        let digest = SHA256.hash(data: Data(publicKey.utf8))
        let bytes = Array(digest)
        let n = max(1, wordCount)
        var words: [String] = []
        words.reserveCapacity(n)
        for i in 0..<n {
            // 6 bits per word → index into the 64-word list. Wraps across the
            // 32-byte digest so wordCount can exceed the byte count safely.
            let index = Int(bytes[i % bytes.count]) & 0x3F
            words.append(wordlist[index])
        }
        return words.joined(separator: "-")
    }

    /// 64 short, visually distinct, unambiguous words (6 bits each). Avoids
    /// homophones and easily-confused pairs so a spoken/read comparison is
    /// reliable. Order is load-bearing — never reorder or the phrase for an
    /// existing key would change.
    static let wordlist: [String] = [
        "amber", "anchor", "apple", "arrow", "basil", "beacon", "birch", "bison",
        "bloom", "bronze", "cabin", "cedar", "cinder", "clover", "comet", "copper",
        "coral", "cosmo", "delta", "ember", "falcon", "fern", "flint", "forest",
        "garnet", "glacier", "harbor", "hazel", "ivory", "jade", "kelp", "lagoon",
        "lemon", "lily", "lunar", "maple", "marble", "meadow", "nectar", "nimbus",
        "oasis", "olive", "onyx", "opal", "pebble", "pine", "quartz", "quiet",
        "raven", "river", "saffron", "sage", "slate", "spruce", "stone", "tiger",
        "topaz", "tulip", "umber", "velvet", "willow", "yarrow", "zephyr", "zinc",
    ]
}
