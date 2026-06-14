#if os(iOS)
import SwiftUI
import Observation
import ConduitCore
import SessionFeature
import DesignSystem

/// Single source of truth for the global ``AgentIsland``.
///
/// The store derives `agents` on demand from the live `SessionViewModel` it's
/// handed. Because the read happens inside the computed property and SwiftUI's
/// `@Observable` tracking is transitive, any view reading `store.agents`
/// re-renders when the session mutates (`status`, `isExecutingUnified`, `cwd`).
///
/// `agents` surfaces **only** the real live session (see below) — no demo data
/// ships. The expandable multi-agent island with its `AgentDemoData` roster
/// exists only in the DEBUG gallery; it is never read here.
@MainActor
@Observable
public final class AgentHUDStore {
    /// The live session backing the island's primary agent.
    public var session: SessionViewModel?

    /// Pending approvals across the global inbox (drives the amber badge).
    public var pendingApprovals: Int = 0

    public init() {}

    /// Agents shown in the status header: just the real live session. Returns
    /// empty when nothing is live so the header is contextual — it appears only
    /// when there's a real session to surface, never as always-on mock data.
    /// (The expandable multi-agent island with its demo roster lives only in the
    /// debug gallery now.)
    public var agents: [AgentInfo] {
        guard let vm = session, !Self.isDisconnected(vm) else { return [] }
        let state = Self.state(for: vm)
        let primary = AgentInfo(
            id: vm.host.id.raw,                       // stable id across re-renders
            name: vm.host.name,
            agentKey: .claudeCode,
            host: vm.host.name,
            cwd: vm.cwd,
            state: state,
            pendingApprovals: pendingApprovals
        )
        return [primary]
    }

    static func isDisconnected(_ vm: SessionViewModel) -> Bool {
        if case .disconnected = vm.status { return true }
        return false
    }

    /// Maps connection status to the island state. Mirrors `SessionView`.
    static func state(for vm: SessionViewModel) -> AgentState {
        switch vm.status {
        case .connecting:   return .thinking
        case .connected:    return vm.isExecutingUnified ? .streaming : .done
        case .disconnected: return .offline
        case .suspended:    return .offline
        case .reconnecting: return .thinking
        case .failed:       return .error
        }
    }
}
#endif
