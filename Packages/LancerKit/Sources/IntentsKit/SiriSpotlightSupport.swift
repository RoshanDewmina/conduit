#if canImport(AppIntents)
import Foundation

/// Privacy-safe gate for App Intents Spotlight indexing (I2, adapted from the
/// parked `cursor/siri-phase2-fixes-9257` branch's `IntentEntitySpotlightSupport`
/// — that branch's `Intent*Record`/`*IndexFields` types belonged to the
/// superseded `IntentEntityCatalog` model and don't exist anymore, but the
/// underlying safety concern they encoded is still real and still applies to
/// the current `IntentsKit` `*Entity` types).
///
/// The system-wide Spotlight index is a materially different exposure surface
/// than an in-app Siri dialog or disambiguation list: it's a system service
/// database that persists on-disk outside the app sandbox and surfaces in
/// system-wide search, not just inside a live conversation with Siri.
/// `RunEntity.title` (a run's raw prompt text) and `ApprovalEntity.title`
/// (which embeds the literal command/question being approved, via
/// `IntentsKitSupport.approvalActionSummary`) are already spoken aloud and
/// shown in Siri disambiguation lists today (accepted for that narrower
/// surface by D2/D3/I1) — but that doesn't make them safe to also copy
/// verbatim into the broader Spotlight index. `SiriEntityIndexer` runs every
/// entity's indexable text through `containsForbiddenIndexMaterial` before
/// indexing it and skips (rather than redacts) anything that trips the
/// heuristic, so a prompt/command/question that looks like it embeds a
/// credential never reaches Spotlight at all.
@available(iOS 17.0, *)
public enum SiriSpotlightSupport {
    /// Named index domain so Spotlight indexing/removal calls share one
    /// on-device index rather than mixing into the default unnamed one.
    public static let spotlightDomain = "dev.lancer.mobile"

    /// Returns `true` when `text` looks like it embeds a secret/credential.
    /// Deliberately a coarse, fail-closed heuristic (false positives just skip
    /// indexing one item; false negatives are the actual risk) rather than a
    /// precise secret scanner — matches the bar the old branch's version set.
    public static func containsForbiddenIndexMaterial(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let forbidden = [
            "api_key", "apikey", "secret", "password", "token", "bearer ",
            "private key", "ssh-rsa", "-----begin",
        ]
        return forbidden.contains { lowered.contains($0) }
    }

    /// Filters `entities` down to the ones safe to hand to
    /// `CSSearchableIndex.indexAppEntities` — i.e. whose `indexableText` does
    /// not trip `containsForbiddenIndexMaterial`. Pure and side-effect-free so
    /// it's testable without touching the real Spotlight index.
    public static func safeEntities<T>(
        _ entities: [T],
        indexableText: (T) -> String
    ) -> [T] {
        entities.filter { !containsForbiddenIndexMaterial(indexableText($0)) }
    }
}

#endif
