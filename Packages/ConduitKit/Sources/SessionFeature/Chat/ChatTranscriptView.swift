#if os(iOS)
import SwiftUI
import ConduitCore
import TerminalEngine
import DesignSystem

// Maps the BlockRenderer's block array onto a chat transcript.
// Each Block becomes a ToolCardView. Input is handled by ChatInputBar
// at the bottom of the parent view — not inline here.

private struct BottomOffsetKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = .zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

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
    @State private var isAtBottom = true
    @State private var maxBottomY: CGFloat = 0

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
                    ForEach(Array(blocks.blocks.enumerated()), id: \.element.id) { index, block in
                        if index > 0 {
                            timestampDivider(between: blocks.blocks[index - 1], and: block)
                        }
                        if !block.command.isEmpty {
                            userBubble(for: block)
                        }
                        toolCard(for: block)
                            .id(block.id)
                    }
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: BottomOffsetKey.self, value: geo.frame(in: .global).minY)
                    }
                    .frame(height: 0)
                    .id("bottom")
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
                guard isAtBottom else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: blocks.blocks.last?.chunks.count) { _, _ in
                guard isAtBottom else { return }
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onPreferenceChange(BottomOffsetKey.self) { bottomMinY in
                if maxBottomY == 0 {
                    maxBottomY = bottomMinY
                }
                if bottomMinY > maxBottomY {
                    maxBottomY = bottomMinY
                }
                let dist = maxBottomY - bottomMinY
                withAnimation(.easeOut(duration: 0.15)) {
                    isAtBottom = dist < 100
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isAtBottom {
                    Button {
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                        isAtBottom = true
                    } label: {
                        Text("↓ latest")
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(t.surface2)
                            .clipShape(Capsule())
                    }
                    .transition(.opacity)
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                }
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

    // MARK: - User prompt bubble (P1.2)

    @ViewBuilder
    private func userBubble(for block: Block) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("You")
                .font(.dsMonoPt(10))
                .foregroundStyle(t.text3)
            Text(block.command)
                .font(.dsMonoPt(14))
                .foregroundStyle(t.text)
                .lineSpacing(14 * 0.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(t.surface2)
                .clipShape(RoundedRectangle(cornerRadius: t.r1, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 4)
    }

    // MARK: - Timestamp divider (P1.3)

    @ViewBuilder
    private func timestampDivider(between previous: Block, and current: Block) -> some View {
        let prevMinute = Self.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: previous.startedAt)
        let currMinute = Self.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: current.startedAt)
        if prevMinute != currMinute {
            HStack(spacing: 0) {
                DSDivider(.soft)
                Text("─ \(Self.timestampFormatter.string(from: current.startedAt)) ─")
                    .font(.dsMonoPt(10))
                    .foregroundStyle(t.text4)
                    .fixedSize()
                DSDivider(.soft)
            }
            .padding(.vertical, 4)
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let calendar: Calendar = .current

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
