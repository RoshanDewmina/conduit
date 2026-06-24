import Foundation

public struct PolicyPreset: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var description: String
    public var ruleYAML: String

    public init(id: String, name: String, description: String, ruleYAML: String) {
        self.id = id
        self.name = name
        self.description = description
        self.ruleYAML = ruleYAML
    }
}

public final class PolicyPresetStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let storageKey = "lancer.policyPresets"

    public static let shared = PolicyPresetStore()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        seedBuiltinsIfNeeded()
    }

    public func all() -> [PolicyPreset] {
        guard let data = defaults.data(forKey: storageKey),
              let presets = try? JSONDecoder().decode([PolicyPreset].self, from: data) else {
            return []
        }
        return presets
    }

    public func save(_ preset: PolicyPreset) {
        var presets = all()
        if let idx = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[idx] = preset
        } else {
            presets.append(preset)
        }
        persist(presets)
    }

    public func delete(id: String) {
        let presets = all().filter { $0.id != id }
        persist(presets)
    }

    public func importJSON(_ data: Data) throws {
        let incoming = try JSONDecoder().decode([PolicyPreset].self, from: data)
        var presets = all()
        for preset in incoming {
            if let idx = presets.firstIndex(where: { $0.id == preset.id }) {
                presets[idx] = preset
            } else {
                presets.append(preset)
            }
        }
        persist(presets)
    }

    public func exportJSON() throws -> Data {
        try JSONEncoder().encode(all())
    }

    private func persist(_ presets: [PolicyPreset]) {
        if let data = try? JSONEncoder().encode(presets) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func seedBuiltinsIfNeeded() {
        guard defaults.data(forKey: storageKey) == nil else { return }
        persist([.prodStrict, .devRelaxed])
    }
}

public extension PolicyPreset {
    static let prodStrict = PolicyPreset(
        id: "builtin.prod-strict",
        name: "prod-strict",
        description: "No rm or push. Escalates file writes outside src/.",
        ruleYAML: """
default: ask
rules:
  - effect: deny
    kind: credential
  - effect: deny
    kind: network
  - effect: deny
    maxRisk: critical
  - effect: deny
    maxRisk: high
  - effect: ask
"""
    )

    static let devRelaxed = PolicyPreset(
        id: "builtin.dev-relaxed",
        name: "dev-relaxed",
        description: "Auto-allows reads and builds. Asks on writes and network.",
        ruleYAML: """
default: ask
rules:
  - effect: deny
    kind: credential
  - effect: allow
    maxRisk: low
    kind: command
  - effect: allow
    kind: read
  - effect: ask
    kind: patch
  - effect: ask
    kind: network
  - effect: ask
"""
    )
}
