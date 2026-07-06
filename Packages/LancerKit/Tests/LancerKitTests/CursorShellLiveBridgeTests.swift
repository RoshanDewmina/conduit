#if os(iOS)
import Foundation
import Testing
@testable import AppFeature

@Suite("CursorShellLiveBridge")
@MainActor
struct CursorShellLiveBridgeTests {
    @Test("live workspace hydration includes a sorted All Repos aggregate")
    func allReposAggregateUsesLiveThreads() {
        let bridge = CursorShellLiveBridge()
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)

        bridge.reloadWorkspaceThreads([
            "lancer-ios": [
                CursorShellLiveBridge.ThreadRow(
                    id: "conv-old",
                    title: "Older iOS thread",
                    repoName: "lancer-ios",
                    updatedAt: older
                )
            ],
            "push-backend": [
                CursorShellLiveBridge.ThreadRow(
                    id: "conv-new",
                    title: "Newer backend thread",
                    repoName: "push-backend",
                    updatedAt: newer
                )
            ],
        ])

        #expect(bridge.workspaces.map(\.name) == ["lancer-ios", "push-backend"])
        #expect(bridge.threads(for: "lancer-ios").map(\.title) == ["Older iOS thread"])
        #expect(bridge.threads(for: "All Repos").map(\.title) == ["Newer backend thread", "Older iOS thread"])
    }
}
#endif
