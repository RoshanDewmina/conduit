#if os(iOS)
import SwiftUI

/// Bridges SwiftUI `ScenePhase` changes to async callbacks so that
/// engine-layer objects (which cannot import SwiftUI) can react to
/// foreground / background transitions.
///
/// Usage — attach to your top-level view:
/// ```swift
/// @State private var observer = ScenePhaseObserver(
///     onBecomeActive: { await session.handleSceneActive() },
///     onBackground:   { await session.handleSceneBackground() }
/// )
/// @Environment(\.scenePhase) private var scenePhase
///
/// var body: some View {
///     ContentView()
///         .onChange(of: scenePhase) { _, newPhase in
///             Task { await observer.scenePhaseChanged(to: newPhase) }
///         }
/// }
/// ```
@MainActor
public final class ScenePhaseObserver: ObservableObject {
    private let onBecomeActive: () async -> Void
    private let onBackground: () async -> Void

    public init(
        onBecomeActive: @escaping () async -> Void,
        onBackground: @escaping () async -> Void
    ) {
        self.onBecomeActive = onBecomeActive
        self.onBackground = onBackground
    }

    /// Call this from a `.onChange(of: scenePhase)` modifier.
    public func scenePhaseChanged(to phase: ScenePhase) async {
        switch phase {
        case .active:
            await onBecomeActive()
        case .background:
            await onBackground()
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}

// MARK: - ViewModifier convenience

/// A convenience modifier that connects `ScenePhaseObserver` to a view's
/// `scenePhase` environment value automatically.
public struct ScenePhaseObserverModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let observer: ScenePhaseObserver

    public func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, newPhase in
                Task { await observer.scenePhaseChanged(to: newPhase) }
            }
    }
}

public extension View {
    func observeScenePhase(with observer: ScenePhaseObserver) -> some View {
        modifier(ScenePhaseObserverModifier(observer: observer))
    }
}
#endif
