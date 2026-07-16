import Foundation

/// Settings copy for connections + governance surfaces.
public enum AppSettingsCopy {
    public static let connectionsSectionTitle = "Connections"
    public static let policyGovernanceTitle = "Policy & Governance"
    public static let policyRowTitle = "Policy"
    public static let policyRowDetail = "View rules and edit host policy YAML"
    public static let auditRowTitle = "Audit feed"
    public static let auditRowDetail = "Recent host audit entries"
    public static let emergencyStopSectionTitle = "Emergency Stop"
    public static let emergencyStopButtonTitle = "Emergency Stop"
    public static let emergencyStopConfirmTitle = "Emergency Stop?"
    public static let emergencyStopConfirmMessage =
        "Stops all runs and blocks new launches until re-enabled. This cannot be undone from a cancelled confirmation — only confirm if you intend to halt the host."
    public static let emergencyStopConfirmAction = "Stop all runs"
}
