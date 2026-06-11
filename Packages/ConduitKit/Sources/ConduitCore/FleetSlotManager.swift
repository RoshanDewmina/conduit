import Foundation

/// Platform-independent slot management logic shared by ``FleetStore`` (iOS)
/// and exercised directly in cross-platform unit tests.
///
/// `T` must be `Identifiable` with `ID == UUID` so that `remove(id:)` can
/// find slots without needing any platform-specific types.
public struct FleetSlotManager<T: Identifiable> where T.ID == UUID {

    /// The hard cap on simultaneous sessions. Matches ``FleetStore.maxSlots``.
    public static var maxSlots: Int { 3 }

    /// All currently registered slots, in insertion order.
    public private(set) var slots: [T] = []

    public init() {}

    /// Whether the store has reached capacity.
    public var isFull: Bool { slots.count >= Self.maxSlots }

    /// Add a slot. Silently ignores the call when the store is at capacity.
    public mutating func add(_ slot: T) {
        guard !isFull else { return }
        slots.append(slot)
    }

    /// Remove the slot with the given id, if present.
    public mutating func remove(id: UUID) {
        slots.removeAll { $0.id == id }
    }

    /// Update a slot in place when `id` matches.
    public mutating func update(id: UUID, _ body: (inout T) -> Void) {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { return }
        body(&slots[index])
    }
}
