import Foundation
import LancerCore

/// Per-app permission-mode persistence for `AutonomyPreset`.
/// Default matches onboarding's Balanced tier → `.autoSafeWrites`
/// (`OnboardingCautionLevel.balanced.mappedPreset`).
///
/// Local `@AppStorage` is a cache only — the daemon coarse mode
/// (`PermissionMode` via `GovernanceHostActions`) is authoritative. Use
/// `AutonomyPreset.coarsePermissionMode` / `.reflecting(coarseMode:preferred:)`
/// when pushing or hydrating; never treat storage alone as confirmed.
public enum AutonomySelection {
    public static let storageKey = "lancer.autonomy.preset"
    public static let `default`: AutonomyPreset = .autoSafeWrites

    public static func resolve(_ raw: String?) -> AutonomyPreset {
        guard let raw else { return Self.default }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Self.default }
        return AutonomyPreset(rawValue: trimmed) ?? Self.default
    }

    public static func load(from defaults: UserDefaults = .standard) -> AutonomyPreset {
        resolve(defaults.string(forKey: storageKey))
    }

    public static func save(_ preset: AutonomyPreset, to defaults: UserDefaults = .standard) {
        defaults.set(preset.rawValue, forKey: storageKey)
    }

    /// Coarse relay mode for a stored/raw preset string (fail-closed via
    /// `resolve` → `.autoSafeWrites` → `.ask` on unknown input).
    public static func coarsePermissionMode(forRaw raw: String?) -> PermissionMode {
        resolve(raw).coarsePermissionMode
    }
}
