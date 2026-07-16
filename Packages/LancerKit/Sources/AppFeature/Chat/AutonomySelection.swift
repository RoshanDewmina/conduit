import Foundation
import LancerCore

/// Per-app permission-mode persistence for `AutonomyPreset`.
/// Default matches onboarding's Balanced tier → `.autoSafeWrites`
/// (`OnboardingCautionLevel.balanced.mappedPreset`).
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
}
