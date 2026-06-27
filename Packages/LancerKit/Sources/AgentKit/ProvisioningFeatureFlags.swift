import Foundation

/// Feature flags for multi-cloud provisioning (Phase 3).
public enum ProvisioningFeatureFlags {
    private static let lightsailKey = "lancerLightsailProvisioningEnabled"

    /// When true, AWS Lightsail appears in the provisioning wizard (release builds).
    public static var lightsailEnabled: Bool {
        #if DEBUG
        if UserDefaults.standard.object(forKey: lightsailKey) == nil {
            return true
        }
        #endif
        return UserDefaults.standard.bool(forKey: lightsailKey)
    }

    public static func setLightsailEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: lightsailKey)
    }

    private static let managedCloudKey = "lancerManagedCloudEnabled"

    /// When true, the Lancer Cloud (hosted runtime) option appears in the add-host flow.
    public static var managedCloudEnabled: Bool {
        UserDefaults.standard.bool(forKey: managedCloudKey)
    }

    public static func setManagedCloudEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: managedCloudKey)
    }
}
