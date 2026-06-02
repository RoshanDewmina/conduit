#if canImport(UIKit) && canImport(SwiftTerm)
import SwiftUI
import UIKit
import SwiftTerm
import ConduitCore

/// A shareable handle that lets external code feed bytes into a
/// `RawTerminalView` without knowing about UIKit / SwiftTerm.
///
/// Create one handle per terminal session, pass it to
/// `RawTerminalView.init(feedHandle:...)` **and** keep a reference in
/// `PTYBridge` so the bridge can yield bytes via `handle.yield(_:)`.
public final class TerminalFeedHandle: @unchecked Sendable {
    private let (stream, continuation): (AsyncStream<[UInt8]>, AsyncStream<[UInt8]>.Continuation)

    /// The async stream consumed internally by `RawTerminalView`.
    var feedStream: AsyncStream<[UInt8]> { stream }

    public init() {
        (stream, continuation) = AsyncStream<[UInt8]>.makeStream()
    }

    /// Push a byte chunk into the terminal from any context.
    public func yield(_ bytes: [UInt8]) {
        continuation.yield(bytes)
    }

    /// Signal end-of-stream (PTY closed).
    public func finish() {
        continuation.finish()
    }
}

/// `UIViewRepresentable` host for SwiftTerm. Used in Raw mode (TUI programs
/// like vim, htop, tmux).
///
/// ## Feeding bytes
/// There are two feeding modes:
/// 1. **Handle mode** (preferred for `PTYBridge`): pass a `TerminalFeedHandle`
///    to `init(feedHandle:onUserBytes:onResize:)`. Call `handle.yield(_:)` to
///    push bytes from any isolation context.
/// 2. **Stream mode** (legacy): pass an `AsyncStream<[UInt8]>` directly via
///    `init(feed:onUserBytes:onResize:)`.
///
/// User input flows back out via `onUserBytes`.
public struct RawTerminalView: UIViewRepresentable {
    public final class Coordinator: NSObject, @preconcurrency TerminalViewDelegate, UIGestureRecognizerDelegate {
        public var onUserBytes: (ArraySlice<UInt8>) -> Void
        public var onResize: (Int, Int) -> Void
        public weak var view: TerminalView?

        // Pinch-to-zoom state
        var baseFontSize: CGFloat = {
            let stored = UserDefaults.standard.double(forKey: "terminalFontSize")
            return CGFloat(stored > 0 ? stored : 13)
        }()

        // Cursor drag state — driven by a UIPanGestureRecognizer (no long-press delay).
        var cursorDragAccumX: CGFloat = 0
        var cursorDragAccumY: CGFloat = 0
        var cursorDragLastLocation: CGPoint = .zero
        var cursorDragOnBytes: (([UInt8]) -> Void)?

        public init(
            onUserBytes: @escaping (ArraySlice<UInt8>) -> Void,
            onResize: @escaping (Int, Int) -> Void
        ) {
            self.onUserBytes = onUserBytes
            self.onResize = onResize
        }

        public func send(source: TerminalView, data: ArraySlice<UInt8>) {
            onUserBytes(data)
        }

        // MARK: - Pinch to zoom

        @objc func handlePinch(_ gr: UIPinchGestureRecognizer) {
            guard let term = view else { return }
            switch gr.state {
            case .changed:
                let newSize = (baseFontSize * gr.scale).clamped(to: 9...24)
                term.font = UIFont.monospacedSystemFont(ofSize: newSize, weight: .regular)
            case .ended:
                let newSize = (baseFontSize * gr.scale).clamped(to: 9...24)
                baseFontSize = newSize
                UserDefaults.standard.set(Double(newSize), forKey: "terminalFontSize")
                term.font = UIFont.monospacedSystemFont(ofSize: newSize, weight: .regular)
            case .cancelled, .failed:
                term.font = UIFont.monospacedSystemFont(ofSize: baseFontSize, weight: .regular)
            default:
                break
            }
        }

        // MARK: - Gesture cursor movement (immediate pan — no long-press delay)

        /// Pan recognizer replaces the 350 ms long-press. Movement sends arrow
        /// keys once the accumulated translation exceeds a 12 pt dead-zone,
        /// preventing accidental triggers on short taps.
        @objc func handleCursorPan(_ gr: UIPanGestureRecognizer) {
            switch gr.state {
            case .began:
                cursorDragAccumX = 0
                cursorDragAccumY = 0
                cursorDragLastLocation = gr.location(in: gr.view)
            case .changed:
                let loc = gr.location(in: gr.view)
                let deltaX = loc.x - cursorDragLastLocation.x
                let deltaY = loc.y - cursorDragLastLocation.y
                cursorDragLastLocation = loc
                cursorDragAccumX += deltaX
                cursorDragAccumY += deltaY
                let threshold: CGFloat = 12
                while cursorDragAccumX > threshold {
                    sendArrowKey([0x1b, 0x5b, 0x43])  // right
                    cursorDragAccumX -= threshold
                }
                while cursorDragAccumX < -threshold {
                    sendArrowKey([0x1b, 0x5b, 0x44])  // left
                    cursorDragAccumX += threshold
                }
                while cursorDragAccumY < -threshold {
                    sendArrowKey([0x1b, 0x5b, 0x41])  // up
                    cursorDragAccumY += threshold
                }
                while cursorDragAccumY > threshold {
                    sendArrowKey([0x1b, 0x5b, 0x42])  // down
                    cursorDragAccumY -= threshold
                }
            default:
                break
            }
        }

        private func sendArrowKey(_ bytes: [UInt8]) {
            cursorDragOnBytes?(bytes)
            if UserDefaults.standard.object(forKey: "terminalHapticFeedback") == nil ||
                UserDefaults.standard.bool(forKey: "terminalHapticFeedback") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }

        // MARK: - UIGestureRecognizerDelegate

        public func gestureRecognizer(
            _ gr: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            guard newCols > 0, newRows > 0 else { return }
            onResize(newCols, newRows)
        }

        public func setTerminalTitle(source: TerminalView, title: String) {}
        public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        public func scrolled(source: TerminalView, position: Double) {}
        public func clipboardCopy(source: TerminalView, content: Data) {
            UIPasteboard.general.setData(content, forPasteboardType: "public.utf8-plain-text")
        }
        public func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        public func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        public func bell(source: TerminalView) {}
        public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }

    public let onUserBytes: (ArraySlice<UInt8>) -> Void
    public let onResize:    (Int, Int) -> Void
    public let feed:        AsyncStream<[UInt8]>

    /// Shared feed handle; non-nil when constructed via `init(feedHandle:...)`.
    let feedHandle: TerminalFeedHandle?

    /// When `true`, the inner `TerminalView` disables its own scrolling and
    /// does NOT auto-become first responder. Used for Warp-style block-embedded
    /// terminals where the outer SwiftUI ScrollView handles vertical motion
    /// and only the focused block should claim the keyboard.
    public let inlineEmbedded: Bool

    // MARK: - Initialisers

    /// Legacy initialiser: caller owns the `AsyncStream` and its continuation.
    public init(
        feed: AsyncStream<[UInt8]>,
        onUserBytes: @escaping (ArraySlice<UInt8>) -> Void,
        onResize: @escaping (Int, Int) -> Void,
        inlineEmbedded: Bool = false
    ) {
        self.feed = feed
        self.feedHandle = nil
        self.onUserBytes = onUserBytes
        self.onResize = onResize
        self.inlineEmbedded = inlineEmbedded
    }

    /// Preferred initialiser for `PTYBridge` usage. The `feedHandle` becomes
    /// the source of bytes for the underlying SwiftTerm view.
    public init(
        feedHandle: TerminalFeedHandle,
        onUserBytes: @escaping (ArraySlice<UInt8>) -> Void,
        onResize: @escaping (Int, Int) -> Void,
        inlineEmbedded: Bool = false
    ) {
        self.feed = feedHandle.feedStream
        self.feedHandle = feedHandle
        self.onUserBytes = onUserBytes
        self.onResize = onResize
        self.inlineEmbedded = inlineEmbedded
    }

    public func makeCoordinator() -> Coordinator {
        let c = Coordinator(onUserBytes: onUserBytes, onResize: onResize)
        c.cursorDragOnBytes = { bytes in self.onUserBytes(bytes[...]) }
        return c
    }

    public func makeUIView(context: Context) -> TerminalView {
        let term = TerminalView(frame: .zero)
        term.terminalDelegate = context.coordinator
        term.autocorrectionType = .no
        term.autocapitalizationType = .none
        term.smartDashesType = .no
        term.smartQuotesType = .no
        term.smartInsertDeleteType = .no
        let fontSize = CGFloat(UserDefaults.standard.double(forKey: "terminalFontSize").nonZeroOr(13))
        term.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let theme = TerminalTheme.current
        term.nativeBackgroundColor = UIColor(theme.background)
        term.nativeForegroundColor = UIColor(theme.foreground)
        context.coordinator.view = term
        context.coordinator.baseFontSize = fontSize

        // Pinch to zoom
        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        term.addGestureRecognizer(pinch)

        // Pan gesture for cursor movement — fires immediately (no hold required).
        // A 12 pt dead-zone in the handler prevents accidental cursor moves.
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleCursorPan(_:)))
        pan.delegate = context.coordinator
        term.addGestureRecognizer(pan)

        // Pump PTY bytes into the terminal view from a background task.
        let stream = feed
        Task { @MainActor [weak term] in
            for await bytes in stream {
                term?.feed(byteArray: bytes[...])
            }
        }

        if inlineEmbedded {
            // Outer SwiftUI ScrollView owns scrolling; this terminal is a fixed
            // surface inside a block. Don't auto-claim first responder either —
            // multiple block-embedded terminals would fight for the keyboard.
            term.isScrollEnabled = false
        } else {
            DispatchQueue.main.async { _ = term.becomeFirstResponder() }
        }
        return term
    }

    public func updateUIView(_ view: TerminalView, context: Context) {
        context.coordinator.view = view
    }

    // MARK: - Imperative feed (used by PTYBridge)

    /// Push bytes into the terminal from `PTYBridge` (or any other actor).
    ///
    /// If a `TerminalFeedHandle` is available it routes through the handle;
    /// otherwise the call is a no-op (legacy stream mode pumps itself).
    @MainActor
    public func feed(_ bytes: [UInt8]) {
        feedHandle?.yield(bytes)
    }
}

// MARK: - Helpers

private extension Double {
    func nonZeroOr(_ fallback: Double) -> Double { self > 0 ? self : fallback }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#else

// MARK: - Stub for non-iOS platforms (macOS test host / CLI)

/// No-op stub so `PTYBridge` and `TerminalEngine` compile on macOS.
public struct RawTerminalView: Sendable {

    public init() {}

    /// No-op on non-iOS platforms.
    @MainActor
    public func feed(_ bytes: [UInt8]) {}
}

#endif
