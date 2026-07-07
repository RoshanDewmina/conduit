#if os(iOS)
import LancerCore

/// DaemonChannel already exposes pause/resume/stop/budget/continue RPCs — the bridge
/// is the production run-control channel for SSH-dispatched runs.
extension DaemonChannel: RunControlling {}
#endif
