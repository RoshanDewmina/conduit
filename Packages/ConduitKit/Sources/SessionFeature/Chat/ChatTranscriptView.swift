#if os(iOS)
import SwiftUI
import ConduitCore
import TerminalEngine
import DesignSystem

// Maps the BlockRenderer's block array onto a chat transcript.
// Each Block becomes a ToolCardView. Input is handled by ChatInputBar
// at the bottom of the parent view — not inline here.

public struct ChatTranscriptView: View {
    let blocks: BlockRenderer
    let onLiveBytes: (ArraySlice<UInt8>) -> Void
    let onLiveResize: (Int, Int) -> Void
    let onExplain: (Block) -> Void
    let onRerun: (Block) -> Void
    let onCollapse: (Block) -> Void
    let onStar: (Block) -> Void
    let onLoadOlder: (() -> Void)?

    @Environment(\.conduitTokens) private var t

    // MARK: - Gesture state (Gestures #1 and #2 for block mode)

    @AppStorage("gestureTrackpadEnabled")   private var gestureTrackpadEnabled: Bool = true
    @AppStorage("gestureDoubleTapTab")      private var gestureDoubleTapTab: Bool = true
    @AppStorage("gestureCursorSensitivity") private var gestureCursorSensitivity: Double = 12
    @AppStorage("terminalHapticFeedback")   private var hapticFeedback: Bool = true

    @State private var blockPanArmed = false
    @State private var blockPanAccumX: CGFloat = 0
    @State private var blockPanAccumY: CGFloat = 0
    @State private var blockPanLastTranslation: CGSize = .zero

    public init(
        blocks: BlockRenderer,
        onLiveBytes: @escaping (ArraySlice<UInt8>) -> Void,
        onLiveResize: @escaping (Int, Int) -> Void,
        onExplain: @escaping (Block) -> Void,
        onRerun: @escaping (Block) -> Void,
        onCollapse: @escaping (Block) -> Void,
        onStar: @escaping (Block) -> Void,
        onLoadOlder: (() -> Void)? = nil
    ) {
        self.blocks = blocks
        self.onLiveBytes = onLiveBytes
        self.onLiveResize = onLiveResize
        self.onExplain = onExplain
        self.onRerun = onRerun
        self.onCollapse = onCollapse
        self.onStar = onStar
        self.onLoadOlder = onLoadOlder
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    Color.clear
                        .frame(height: 1)
                        .onAppear { onLoadOlder?() }
                    ForEach(blocks.blocks) { block in
                        toolCard(for: block)
                            .id(block.id)
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            .background(t.surf0)
            // Gesture #1: long-press (150 ms) to arm, then drag to move cursor.
            // simultaneousGesture preserves single-finger scroll.
            .simultaneousGesture(blockCursorPanGesture)
            // Gesture #2: double-tap → Tab.
            .onTapGesture(count: 2) {
                guard gestureDoubleTapTab else { return }
                let tab: [UInt8] = [0x09]
                onLiveBytes(tab[...])
                if hapticFeedback { Haptics.light() }
            }
            .onChange(of: blocks.blocks.count) { _, _ in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: blocks.blocks.last?.chunks.count) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // Extracted so the compiler type-checks ToolCardView's generic init in
    // isolation — inlining it in the ForEach blows the body type-check budget.
    @ViewBuilder
    private func toolCard(for block: Block) -> some View {
        ToolCardView(
            block: block,
            render: blocks.render(block),
            droppedLineCount: blocks.droppedLineCount[block.id] ?? 0,
            liveHandle: blocks.liveBlockHandles[block.id],
            onLiveBytes: { bytes in onLiveBytes(bytes) },
            onLiveResize: { cols, rows in onLiveResize(cols, rows) },
            onExplain: { onExplain(block) },
            onRerun: { onRerun(block) },
            onCollapse: { onCollapse(block) },
            onStar: { onStar(block) }
        ) {
            EmptyView()
        }
    }

    // MARK: - Block-mode cursor pan (Gesture #1)

    private var blockCursorPanGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.15)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard gestureTrackpadEnabled else { return }
                if case .second(_, let drag?) = value {
                    if !blockPanArmed {
                        blockPanArmed = true
                        blockPanAccumX = 0
                        blockPanAccumY = 0
                        blockPanLastTranslation = drag.translation
                        return
                    }
                    let deltaX = drag.translation.width - blockPanLastTranslation.width
                    let deltaY = drag.translation.height - blockPanLastTranslation.height
                    blockPanLastTranslation = drag.translation
                    blockPanAccumX += deltaX
                    blockPanAccumY += deltaY
                    let threshold = CGFloat(gestureCursorSensitivity > 0 ? gestureCursorSensitivity : 12)
                    while blockPanAccumX > threshold {
                        onLiveBytes([0x1b, 0x5b, 0x43][...])  // right
                        blockPanAccumX -= threshold
                        if hapticFeedback { Haptics.light() }
                    }
                    while blockPanAccumX < -threshold {
                        onLiveBytes([0x1b, 0x5b, 0x44][...])  // left
                        blockPanAccumX += threshold
                        if hapticFeedback { Haptics.light() }
                    }
                    while blockPanAccumY < -threshold {
                        onLiveBytes([0x1b, 0x5b, 0x41][...])  // up
                        blockPanAccumY += threshold
                        if hapticFeedback { Haptics.light() }
                    }
                    while blockPanAccumY > threshold {
                        onLiveBytes([0x1b, 0x5b, 0x42][...])  // down
                        blockPanAccumY -= threshold
                        if hapticFeedback { Haptics.light() }
                    }
                }
            }
            .onEnded { _ in
                blockPanArmed = false
                blockPanAccumX = 0
                blockPanAccumY = 0
                blockPanLastTranslation = .zero
            }
    }
}

#endif
