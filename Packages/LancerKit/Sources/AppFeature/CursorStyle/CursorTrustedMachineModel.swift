import Foundation

/// One paired relay machine row for Settings → Trusted machines.
public struct CursorTrustedMachineRow: Identifiable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let shortMachineID: String
    public let isConnected: Bool
    public let pairedAt: Date?
    public let pendingApprovalCount: Int
    public let isInvalid: Bool

    public init(
        id: String,
        displayName: String,
        shortMachineID: String,
        isConnected: Bool,
        pairedAt: Date?,
        pendingApprovalCount: Int,
        isInvalid: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.shortMachineID = shortMachineID
        self.isConnected = isConnected
        self.pairedAt = pairedAt
        self.pendingApprovalCount = pendingApprovalCount
        self.isInvalid = isInvalid
    }
}

public enum CursorTrustedMachineFormatting {
    public static func shortMachineID(_ uuid: UUID) -> String {
        String(uuid.uuidString.prefix(8)).uppercased()
    }

    public static func connectionStatusLabel(isConnected: Bool) -> String {
        isConnected ? "Connected" : "Offline"
    }

    public static func pairedSinceLabel(pairedAt: Date?, now: Date = .now) -> String? {
        guard let pairedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: pairedAt, relativeTo: now)
        return "Paired \(relative)"
    }

    public static func removeConfirmationMessage(
        displayName: String,
        pendingApprovalCount: Int
    ) -> String {
        if pendingApprovalCount > 0 {
            let noun = pendingApprovalCount == 1 ? "approval" : "approvals"
            return """
            \(displayName) has \(pendingApprovalCount) pending \(noun) waiting for your decision. \
            Removing this machine will not decide them — they may become unreachable until you re-pair.

            Remove \(displayName) from this phone?
            """
        }
        return "Remove \(displayName) from this phone? Its pairing data on this device will be deleted. Re-pair from the machine to reconnect."
    }
}

public enum CursorTrustedMachineSnapshot {
    public struct MachineInput: Sendable, Equatable {
        public let id: UUID
        public let displayName: String
        public let pairedAt: Date
        public let isConnected: Bool
        public let isInvalid: Bool

        public init(
            id: UUID,
            displayName: String,
            pairedAt: Date,
            isConnected: Bool,
            isInvalid: Bool
        ) {
            self.id = id
            self.displayName = displayName
            self.pairedAt = pairedAt
            self.isConnected = isConnected
            self.isInvalid = isInvalid
        }
    }

    public static func buildRows(
        machines: [MachineInput],
        pendingApprovalCounts: [UUID: Int]
    ) -> [CursorTrustedMachineRow] {
        machines.map { machine in
            CursorTrustedMachineRow(
                id: machine.id.uuidString,
                displayName: machine.displayName,
                shortMachineID: CursorTrustedMachineFormatting.shortMachineID(machine.id),
                isConnected: machine.isConnected,
                pairedAt: machine.pairedAt,
                pendingApprovalCount: pendingApprovalCounts[machine.id] ?? 0,
                isInvalid: machine.isInvalid
            )
        }
    }

    /// Static example rows for the mock Cursor shell (`liveBridge == nil`).
    public static let mockRows: [CursorTrustedMachineRow] = [
        CursorTrustedMachineRow(
            id: "A1B2C3D4-0000-4000-8000-000000000001",
            displayName: "Mac Mini Studio",
            shortMachineID: "A1B2C3D4",
            isConnected: true,
            pairedAt: Date(timeIntervalSince1970: 1_700_000_000),
            pendingApprovalCount: 0,
            isInvalid: false
        ),
        CursorTrustedMachineRow(
            id: "E5F6G7H8-0000-4000-8000-000000000002",
            displayName: "Home Server",
            shortMachineID: "E5F6G7H8",
            isConnected: false,
            pairedAt: Date(timeIntervalSince1970: 1_650_000_000),
            pendingApprovalCount: 0,
            isInvalid: false
        ),
    ]
}
