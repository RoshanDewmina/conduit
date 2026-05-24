#if os(iOS)
import SwiftUI

/// A layout container that renders a NavigationSplitView on iPad (regular width)
/// and falls back to showing only the sidebar on compact (iPhone / iPhone-sized
/// iPad split-app window), letting AppRoot's existing TabView take over.
public struct AdaptiveRoot<Sidebar: View, Detail: View>: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

    private let sidebar: Sidebar
    private let detail: Detail

    public init(
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        self.detail = detail()
    }

    public var body: some View {
        if hSizeClass == .regular {
            NavigationSplitView {
                sidebar
            } detail: {
                detail
            }
        } else {
            // On compact size class the TabView wrapper in AppRoot provides
            // navigation, so we only expose the sidebar column.
            sidebar
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Regular (iPad)") {
    AdaptiveRoot {
        List { Text("Workspaces") }
    } detail: {
        Text("Session detail")
    }
    .environment(\.horizontalSizeClass, .regular)
}

#Preview("Compact (iPhone)") {
    AdaptiveRoot {
        List { Text("Workspaces") }
    } detail: {
        Text("Session detail")
    }
    .environment(\.horizontalSizeClass, .compact)
}
#endif

#endif
