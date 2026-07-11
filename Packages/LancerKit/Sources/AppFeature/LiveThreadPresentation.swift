import Foundation

/// Identifies one live-send `LiveThreadView` presentation. A fresh id per
/// send ensures `.sheet(item:)` always treats a new send as a new sheet
/// instance, even if the prompt text happens to repeat.
struct LiveThreadIdentifier: Identifiable, Sendable, Hashable {
    let id: UUID
    let prompt: String
    let cwd: String

    init(prompt: String, cwd: String, id: UUID = UUID()) {
        self.id = id
        self.prompt = prompt
        self.cwd = cwd
    }
}

#if os(iOS)
import SwiftUI

/// Shared `.sheet(item:)` presentation for `LiveThreadView`, matching the
/// Workspaces M3 pattern — presenters only set `activeLiveThread`; the
/// bridge send stays inside `LiveThreadView`'s own `.task`.
private struct LiveThreadPresentationModifier: ViewModifier {
    @Binding var activeLiveThread: LiveThreadIdentifier?
    @Environment(ShellLiveBridge.self) private var shellLiveBridge
    @Environment(RelayApprovalIngest.self) private var relayApprovalIngest
    @Environment(RelayQuestionIngest.self) private var relayQuestionIngest
    @Environment(RelayFleetStore.self) private var relayFleetStore

    func body(content: Content) -> some View {
        content
            .sheet(item: $activeLiveThread) { thread in
                LiveThreadView(prompt: thread.prompt, cwd: thread.cwd)
                    .environment(shellLiveBridge)
                    .environment(relayApprovalIngest)
                    .environment(relayQuestionIngest)
                    .environment(relayFleetStore)
            }
    }
}

extension View {
    func liveThreadPresentation(_ activeLiveThread: Binding<LiveThreadIdentifier?>) -> some View {
        modifier(LiveThreadPresentationModifier(activeLiveThread: activeLiveThread))
    }
}
#endif
