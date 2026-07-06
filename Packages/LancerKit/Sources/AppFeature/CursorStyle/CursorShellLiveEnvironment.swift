#if os(iOS)
import SwiftUI

private struct CursorShellLiveBridgeKey: EnvironmentKey {
    static let defaultValue: CursorShellLiveBridge? = nil
}

extension EnvironmentValues {
    var cursorShellLiveBridge: CursorShellLiveBridge? {
        get { self[CursorShellLiveBridgeKey.self] }
        set { self[CursorShellLiveBridgeKey.self] = newValue }
    }
}
#endif
