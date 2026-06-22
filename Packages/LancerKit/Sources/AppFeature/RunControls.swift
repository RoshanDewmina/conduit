#if os(iOS)
import SwiftUI
import DesignSystem
import LancerCore

// MARK: - Streaming output
// Extracted from RunDetailView so NewChatTabView's inline thread can render
// agent output identically without duplicating the caret/composition logic.

/// Renders accumulated run output as a single flowing monospace block with a
/// blinking block caret while the agent is still writing. Concatenating the text
/// (rather than one Text per chunk) lets sub-line token deltas flow inline like a
/// real terminal; the caret is appended via Text composition so it sits right
/// after the last glyph and wraps with the text.
struct StreamingOutputText: View {
    let text: String
    let isStreaming: Bool

    @Environment(\.lancerTokens) private var t

    var body: some View {
        Group {
            if isStreaming {
                // 0.55s blink phase, no per-frame state — TimelineView re-renders the
                // composed Text and we flip the caret's opacity from the wall clock.
                TimelineView(.periodic(from: .now, by: 0.55)) { ctx in
                    let on = Int(ctx.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
                    composed(caretOpacity: on ? 1 : 0.12)
                }
            } else {
                composed(caretOpacity: 0)
            }
        }
        .textSelection(.enabled)
    }

    private func composed(caretOpacity: Double) -> Text {
        let body = Text(text)
            .font(.dsMonoPt(13))
            .foregroundColor(t.termText)
        let caret = Text(isStreaming ? "▋" : "")
            .font(.dsMonoPt(13))
            .foregroundColor(t.termPrompt.opacity(caretOpacity))
        return Text("\(body)\(caret)")
    }
}

// MARK: - Run control bar
// Destructive-left ordering per LANCER_UI_CONSISTENCY_RULES R3.3; equal-width row.
// Shared by RunDetailView (its own page) and NewChatTabView (inline thread).

struct RunControlBar: View {
    let store: RunControlStore
    let isTerminal: Bool
    let failed: Bool
    let exitCode: Int?
    let onStop: () -> Void
    let onShowBudget: () -> Void

    @Environment(\.lancerTokens) private var t

    var body: some View {
        if isTerminal {
            finishedBar
        } else {
            liveControlBar
        }
    }

    private var finishedBar: some View {
        HStack(spacing: 8) {
            Image(systemName: failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(failed ? t.termErr : t.termPrompt)
            Text(failed
                 ? "Run failed\(exitCode.map { " · exit \($0)" } ?? "")"
                 : "Run complete")
                .font(.dsMonoPt(13, weight: .semibold))
                .foregroundStyle(t.text)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(t.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private var liveControlBar: some View {
        HStack(spacing: 8) {
            DSButton("Stop", systemImage: "stop.fill", variant: .destructive, fullWidth: true) {
                Haptics.warning()
                onStop()
            }
            .disabled(!store.canStop)

            if store.canResume {
                DSButton("Resume", systemImage: "play.fill", variant: .secondary, fullWidth: true) {
                    Haptics.selection()
                    Task { await store.resume() }
                }
            } else {
                DSButton("Pause", systemImage: "pause.fill", variant: .secondary, fullWidth: true) {
                    Haptics.selection()
                    Task { await store.pause() }
                }
                .disabled(!store.canPause)
            }

            DSButton("Budget", systemImage: "gauge.with.dots.needle.50percent", variant: .secondary, fullWidth: true) {
                Haptics.selection()
                onShowBudget()
            }
            .disabled(!store.canSetBudget)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }
}

// MARK: - Follow-up bar

struct RunFollowUpBar: View {
    @Binding var text: String
    let isErrorState: Bool
    let onSend: (String) -> Void

    @Environment(\.lancerTokens) private var t

    var body: some View {
        let textEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 10) {
            Text("$")
                .font(.dsMonoPt(15))
                .foregroundStyle(t.info)
                .padding(.leading, 6)
            TextField("follow-up", text: $text, axis: .vertical)
                .font(.dsSansPt(16))
                .foregroundStyle(t.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .disabled(isErrorState)
            if isErrorState {
                DSButton("Reconnect", systemImage: "arrow.clockwise", variant: .primary) {
                    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSend(value.isEmpty ? "/reconnect" : value)
                    text = ""
                }
            } else {
                Button {
                    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    onSend(value)
                    text = ""
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(textEmpty ? t.text4 : t.accentFg)
                        .frame(width: 34, height: 34)
                        .background(textEmpty ? t.surface2 : t.accent, in: Circle())
                }
                .disabled(textEmpty)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(t.surfaceSunk, in: Capsule())
        .overlay(Capsule().stroke(t.border.opacity(0.65), lineWidth: 1))
    }
}

// MARK: - Budget sheet

struct BudgetSheet: View {
    let onSet: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amount = "5.00"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set daily budget")
                .font(.dsDisplayPt(22, weight: .bold))
            HStack(spacing: 8) {
                Text("$").font(.system(size: 16, design: .monospaced)).foregroundStyle(.secondary)
                TextField("5.00", text: $amount)
                    .font(.system(size: 16, design: .monospaced))
                    .keyboardType(.decimalPad)
            }
            .padding(.horizontal, 13).frame(height: 48)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Disabled until the input parses, so "Set cap" can't silently dismiss on bad input.
            DSButton("Set cap", variant: .primary, fullWidth: true) {
                guard let usd = Double(amount) else { return }
                Haptics.success()
                onSet(usd)
                dismiss()
            }
            .disabled(Double(amount) == nil)
        }
        .padding(18)
    }
}

// MARK: - Conversation scroll container
// Auto-scrolls to the bottom as new content streams in, but pauses once the user
// scrolls up to read earlier output (so streaming text doesn't yank them back down),
// surfacing a jump-to-bottom button until they return — mirrors the Vercel AI
// Elements `Conversation`/`ConversationScrollButton` pattern.

struct ConversationScrollView<Content: View>: View {
    let bottomID: String
    let scrollKey: Int
    @ViewBuilder var content: () -> Content

    @State private var isPinnedToBottom = true
    @Environment(\.lancerTokens) private var t

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        content()
                        Color.clear.frame(height: 1).id(bottomID)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                }
                .onScrollGeometryChange(for: Bool.self, of: { geo in
                    geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 60
                }, action: { _, atBottom in
                    isPinnedToBottom = atBottom
                })
                .onChange(of: scrollKey) { _, _ in
                    guard isPinnedToBottom else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
                .onAppear {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }

                if !isPinnedToBottom {
                    Button {
                        Haptics.selection()
                        withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) }
                        isPinnedToBottom = true
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(t.text)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(t.surface))
                            .overlay(Circle().strokeBorder(t.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
            }
        }
    }
}
#endif
