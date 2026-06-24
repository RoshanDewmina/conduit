import Foundation

public enum TeamRole: String, Codable, CaseIterable, Sendable {
    case owner, approver, viewer

    public var capabilities: [String] {
        switch self {
        case .owner:    ["approve", "edit policy", "stop agent"]
        case .approver: ["approve"]
        case .viewer:   ["read-only"]
        }
    }

    public var canApprove: Bool {
        switch self {
        case .owner, .approver: true
        case .viewer:           false
        }
    }
}

public struct TeamMember: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var role: TeamRole

    public init(id: String = UUID().uuidString, name: String, role: TeamRole) {
        self.id = id
        self.name = name
        self.role = role
    }
}

public final class TeamRoleStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let membersKey = "lancer.teamMembers"
    private let onCallKey  = "lancer.teamOnCallID"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        seedIfNeeded()
    }

    private func seedIfNeeded() {
        guard defaults.data(forKey: membersKey) == nil else { return }
        let seed = TeamMember(id: "lancer.self", name: "you", role: .owner)
        save([seed])
        defaults.set(seed.id, forKey: onCallKey)
    }

    private func load() -> [TeamMember] {
        guard let data = defaults.data(forKey: membersKey),
              let members = try? JSONDecoder().decode([TeamMember].self, from: data)
        else { return [] }
        return members
    }

    private func save(_ members: [TeamMember]) {
        guard let data = try? JSONEncoder().encode(members) else { return }
        defaults.set(data, forKey: membersKey)
    }

    public func all() -> [TeamMember] { load() }

    public func add(name: String, role: TeamRole) {
        var members = load()
        members.append(TeamMember(name: name, role: role))
        save(members)
    }

    public func remove(id: String) {
        var members = load()
        members.removeAll { $0.id == id }
        save(members)
        if defaults.string(forKey: onCallKey) == id {
            defaults.removeObject(forKey: onCallKey)
        }
    }

    public func setRole(_ id: String, role: TeamRole) {
        var members = load()
        guard let idx = members.firstIndex(where: { $0.id == id }) else { return }
        members[idx].role = role
        save(members)
    }

    public func setOnCall(_ id: String) {
        defaults.set(id, forKey: onCallKey)
    }

    public func onCallMember() -> TeamMember? {
        guard let id = defaults.string(forKey: onCallKey) else { return nil }
        return load().first { $0.id == id }
    }

    public func currentUserCanApprove() -> Bool {
        load().first { $0.id == "lancer.self" }?.role.canApprove ?? false
    }
}
