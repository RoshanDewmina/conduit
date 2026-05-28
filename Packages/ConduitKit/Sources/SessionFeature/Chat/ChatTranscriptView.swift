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

    @Environment(\.conduitTokens) private var t

    public init(
        blocks: BlockRenderer,
        onLiveBytes: @escaping (ArraySlice<UInt8>) -> Void,
        onLiveResize: @escaping (Int, Int) -> Void,
        onExplain: @escaping (Block) -> Void,
        onRerun: @escaping (Block) -> Void,
        onCollapse: @escaping (Block) -> Void,
        onStar: @escaping (Block) -> Void
    ) {
        self.blocks = blocks
        self.onLiveBytes = onLiveBytes
        self.onLiveResize = onLiveResize
        self.onExplain = onExplain
        self.onRerun = onRerun
        self.onCollapse = onCollapse
        self.onStar = onStar
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(blocks.blocks) { block in
                        ToolCardView(
                            block: block,
                            render: blocks.render(block),
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
                        .id(block.id)
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            .background(t.surf0)
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
}

#endif
