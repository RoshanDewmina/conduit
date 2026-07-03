import Foundation

/// Formats the sidebar's relay-connection footer text. Pulled out of
/// `LancerSidebarView` (iOS-only) so the logic is testable on any host, and
/// so there's exactly one place that decides what the footer says instead of
/// each caller re-deriving it inline.
public enum RelayConnectionStatusText {
    public static func footerText(
        connected: Bool,
        hostCount: Int,
        lastConnectedAt: Date? = nil,
        now: Date = Date()
    ) -> String {
        guard connected else {
            guard let lastConnectedAt else { return "Relay disconnected" }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let relative = formatter.localizedString(for: lastConnectedAt, relativeTo: now)
            return "Relay disconnected · last seen \(relative)"
        }
        switch hostCount {
        case 0: return "Relay connected"
        case 1: return "Relay connected · 1 host"
        default: return "Relay connected · \(hostCount) hosts"
        }
    }
}
