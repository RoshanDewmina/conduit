import Foundation

/// Phantom-typed identifier wrapper. Each domain entity owns its own
/// `TypedID<Tag>` so the compiler refuses to mix host ids with session ids.
///
/// We implement `Hashable`/`Codable`/`Sendable` manually because the `Tag`
/// generic is a phantom (uninhabited) type and Swift cannot synthesize
/// conformances when `Tag` has no constraints.
public struct TypedID<Tag>: @unchecked Sendable {
    public let raw: UUID
    public init(_ raw: UUID = .init()) { self.raw = raw }
    public var uuidString: String { raw.uuidString }
}

extension TypedID: Equatable {
    public static func == (lhs: TypedID<Tag>, rhs: TypedID<Tag>) -> Bool {
        lhs.raw == rhs.raw
    }
}

extension TypedID: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(raw) }
}

extension TypedID: Codable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        self.init(try c.decode(UUID.self))
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }
}

extension TypedID: CustomStringConvertible {
    public var description: String { raw.uuidString }
}

// MARK: - Phantom tags (uninhabited)

public enum HostTag {}
public enum SessionTag {}
public enum BlockTag {}
public enum ApprovalTag {}
public enum SnippetTag {}
public enum KeyTag {}
public enum RelayMachineTag {}

public typealias HostID         = TypedID<HostTag>
public typealias SessionID      = TypedID<SessionTag>
public typealias BlockID        = TypedID<BlockTag>
public typealias ApprovalID     = TypedID<ApprovalTag>
public typealias SnippetID      = TypedID<SnippetTag>
public typealias KeyID          = TypedID<KeyTag>
public typealias RelayMachineID = TypedID<RelayMachineTag>
