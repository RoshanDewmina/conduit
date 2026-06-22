#if DEBUG && os(iOS)
import SwiftUI
import DesignSystem

// MARK: - States gallery (LANCER_GALLERY=states)
// Shows every Phase 6 state atom: error cards, skeletons, slow overlay, offline banner.

struct StatesGalleryScreen: View {
    @Environment(\.lancerTokens) private var t
    @State private var showSlowOverlay = false

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // MARK: Offline banner
                    sectionHead("DSOfflineState")
                    DSOfflineState(onDismiss: {})
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)

                    // MARK: Skeleton rows
                    sectionHead("DSSkeletonList")
                    DSSkeletonList(count: 4)
                        .padding(.bottom, 24)

                    // MARK: Error cards
                    sectionHead("DSTypedErrorCard — auth")
                    DSTypedErrorCard(error: .authRejected, onPrimary: {}, onSecondary: {})
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    sectionHead("DSTypedErrorCard — network")
                    DSTypedErrorCard(error: .hostUnreachable, onPrimary: {}, onSecondary: {})
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    sectionHead("DSTypedErrorCard — host key")
                    DSTypedErrorCard(error: .hostKeyMismatch, onPrimary: {}, onSecondary: {})
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    sectionHead("DSTypedErrorCard — DNS")
                    DSTypedErrorCard(error: .dnsFailed, onPrimary: {}, onSecondary: {})
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    // MARK: Slow overlay trigger
                    sectionHead("DSSlowOverlay")
                    DSButton("show slow overlay", variant: .secondary, size: .md, mono: true) {
                        showSlowOverlay = true
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .fullScreenCover(isPresented: $showSlowOverlay) {
            DSSlowOverlay(
                message: "still trying…",
                onCancel: { showSlowOverlay = false },
                onRetry: { showSlowOverlay = false }
            )
        }
    }

    private func sectionHead(_ title: String) -> some View {
        Text(title)
            .font(.dsMonoPt(10, weight: .medium))
            .foregroundStyle(t.text3)
            .tracking(0.8)
            .textCase(.uppercase)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }
}
#endif
