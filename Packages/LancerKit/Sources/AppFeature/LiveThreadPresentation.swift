import Foundation
import LancerCore

/// Identifies one live-send `LiveThreadView` presentation. A fresh id per
/// send ensures `.sheet(item:)` always treats a new send as a new sheet
/// instance, even if the prompt text happens to repeat.
struct LiveThreadIdentifier: Identifiable, Sendable, Hashable {
    let id: UUID
    let prompt: String
    let cwd: String
    let attachments: [ConversationAttachmentReference]
    /// Set when this presentation is a follow-up on an already-existing
    /// conversation (e.g. from `ThreadDetailView`) — `LiveThreadView` uses
    /// this to call `bridge.sendFollowUp(conversationID:)` and continue the
    /// same thread instead of `bridge.send()` starting a brand-new one.
    /// `nil` for the New Chat composer's genuinely-new-conversation flow.
    let existingConversationID: String?

    init(
        prompt: String,
        cwd: String,
        attachments: [ConversationAttachmentReference] = [],
        existingConversationID: String? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.prompt = prompt
        self.cwd = cwd
        self.attachments = attachments
        self.existingConversationID = existingConversationID
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
    @Environment(WorkspaceDataStore.self) private var workspaceDataStore

    func body(content: Content) -> some View {
        content
            .sheet(item: $activeLiveThread) { thread in
                LiveThreadView(
                    prompt: thread.prompt,
                    cwd: thread.cwd,
                    attachments: thread.attachments,
                    existingConversationID: thread.existingConversationID
                )
                    .environment(shellLiveBridge)
                    .environment(relayApprovalIngest)
                    .environment(relayQuestionIngest)
                    .environment(relayFleetStore)
                    .environment(workspaceDataStore)
                    .onDisappear {
                        shellLiveBridge.resetForNewThread()
                    }
            }
    }
}

extension View {
    func liveThreadPresentation(_ activeLiveThread: Binding<LiveThreadIdentifier?>) -> some View {
        modifier(LiveThreadPresentationModifier(activeLiveThread: activeLiveThread))
    }
}
#endif
