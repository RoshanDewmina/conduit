#if canImport(UIKit)
import UIKit

/// Thin haptics layer. Calls are no-ops on the simulator.
@MainActor
public enum Haptics {
    public static func light()     { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    public static func medium()    { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    public static func rigid()     { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    public static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    public static func success()   { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    public static func warning()   { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    public static func error()     { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}
#else
public enum Haptics {
    public static func light()     {}
    public static func medium()    {}
    public static func rigid()     {}
    public static func selection() {}
    public static func success()   {}
    public static func warning()   {}
    public static func error()     {}
}
#endif
