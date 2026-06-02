#if canImport(UIKit)
import UIKit
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Thin haptics layer. Calls are no-ops on the simulator.
@MainActor
public enum Haptics {
    public static var hapticsEnabled: Bool {
        let defaults = UserDefaults.standard
        let key = "terminalHapticFeedback"
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }

    public static func light()     { guard hapticsEnabled else { return }; UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    public static func medium()    { guard hapticsEnabled else { return }; UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    public static func rigid()     { guard hapticsEnabled else { return }; UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    public static func selection() { guard hapticsEnabled else { return }; UISelectionFeedbackGenerator().selectionChanged() }
    public static func success()   { guard hapticsEnabled else { return }; UINotificationFeedbackGenerator().notificationOccurred(.success) }
    public static func warning()   { guard hapticsEnabled else { return }; UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    public static func error()     { guard hapticsEnabled else { return }; UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

#if canImport(SwiftUI)
@available(iOS 17.0, *)
public extension View {
    @ViewBuilder
    func conduitSensoryFeedback<T: Equatable>(
        _ feedback: SensoryFeedback,
        trigger: T,
        enabled: Bool = Haptics.hapticsEnabled
    ) -> some View {
        if enabled {
            sensoryFeedback(feedback, trigger: trigger)
        } else {
            self
        }
    }
}
#endif
#else
public enum Haptics {
    public static var hapticsEnabled: Bool { false }
    public static func light()     {}
    public static func medium()    {}
    public static func rigid()     {}
    public static func selection() {}
    public static func success()   {}
    public static func warning()   {}
    public static func error()     {}
}
#endif
