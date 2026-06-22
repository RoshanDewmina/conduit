import Foundation
import HostControlKit
import LancerCore

/// Connection state for the local `lancerd` control socket.
enum ConnectionState: Equatable {
    case unknown
    case connected
    case unreachable(String)
}

/// Observable host-state model shared by the menu bar extra and the
/// management window. Polls `lancerd` over `HostControlKit` on a timer;
/// renders cleanly as "stopped/unreachable" when the daemon isn't running.
@MainActor
@Observable
final class HostModel {
    private(set) var connection: ConnectionState = .unknown
    private(set) var doctor: DoctorReport?
    private(set) var status: AgentStatusSnapshot?
    private(set) var drift: DriftReport?
    private(set) var driftError: String?
    private(set) var lastRefreshed: Date?

    /// Set by the menu bar's "Pair device" action; `ManagementView` consumes
    /// (and clears) it on appear to jump straight to Devices and present the
    /// pairing sheet, since the menu bar and management window are separate
    /// SwiftUI `Scene`s with no direct navigation link between them.
    var pendingPairingRequest = false

    private var pollTask: Task<Void, Never>?

    var activeAgentCount: Int {
        guard let status else { return 0 }
        return status.agents.reduce(0) { $0 + ($1.runningCount ?? 0) }
    }

    // ponytail: AgentStatusSnapshot has no dedicated "needs attention" field
    // yet — approximate with agents that report a session but aren't
    // currently running (idle-with-history). Revisit once lancerd exposes a
    // real attention/approval-pending signal on the snapshot.
    var attentionCount: Int {
        guard let status else { return 0 }
        return status.agents.filter { ($0.sessionCount > 0) && ($0.runningCount ?? 0) == 0 }.count
    }

    var relayCheck: DoctorCheckResult? {
        doctor?.checks.first { $0.name.localizedCaseInsensitiveContains("relay") }
    }

    var residentDaemonCheck: DoctorCheckResult? {
        doctor?.checks.first { $0.name.localizedCaseInsensitiveContains("resident daemon") }
    }

    init() {}

    func refresh() async {
        let client = HostServiceClient()
        do {
            try await client.connect()
            _ = try await client.ping()
            let doctorReport = try await client.doctor()
            let statusSnapshot = try await client.status()
            doctor = doctorReport
            status = statusSnapshot
            connection = .connected
        } catch let error as HostServiceError {
            connection = .unreachable(Self.message(for: error))
        } catch {
            connection = .unreachable(error.localizedDescription)
        }
        lastRefreshed = Date()
    }

    /// Scans a chosen repo folder for instruction-file setup drift. Explicit
    /// root only — never defaults to the daemon cwd, which could walk `/`.
    func scanDrift(root: String) async {
        driftError = nil
        let client = HostServiceClient()
        do {
            try await client.connect()
            drift = try await client.driftScan(root: root)
        } catch let error as HostServiceError {
            driftError = Self.message(for: error)
        } catch {
            driftError = error.localizedDescription
        }
    }

    /// Starts a new phone-pairing session. Opens a fresh, short-lived
    /// `HostServiceClient` rather than reusing the polling client — pairing
    /// is a one-shot RPC, not part of the recurring refresh loop.
    func beginPairing() async throws -> PairingPayload {
        let client = HostServiceClient()
        try await client.connect()
        return try await client.beginPairing()
    }

    func startPolling(interval: Duration = .seconds(3)) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private static func message(for error: HostServiceError) -> String {
        switch error {
        case .notConnected:
            return "Host Service not running"
        case .rpc(let code, let message):
            return "RPC error \(code): \(message)"
        case .decoding:
            return "Malformed response from Host Service"
        case .socket(let detail):
            return detail
        case .versionMismatch:
            return "Host Service version mismatch"
        }
    }
}
