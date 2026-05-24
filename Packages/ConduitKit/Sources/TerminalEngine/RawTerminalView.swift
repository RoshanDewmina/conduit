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
    public final class Coordinator: NSObject, TerminalViewDelegate {
        public var onUserBytes: (ArraySlice<UInt8>) -> Void
        public var onResize: (Int, Int) -> Void
        public weak var view: TerminalView?

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

    // MARK: - Initialisers

    /// Legacy initialiser: caller owns the `AsyncStream` and its continuation.
    public init(
        feed: AsyncStream<[UInt8]>,
        onUserBytes: @escaping (ArraySlice<UInt8>) -> Void,
        onResize: @escaping (Int, Int) -> Void
    ) {
        self.feed = feed
        self.feedHandle = nil
        self.onUserBytes = onUserBytes
        self.onResize = onResize
    }

    /// Preferred initialiser for `PTYBridge` usage. The `feedHandle` becomes
    /// the source of bytes for the underlying SwiftTerm view.
    public init(
        feedHandle: TerminalFeedHandle,
        onUserBytes: @escaping (ArraySlice<UInt8>) -> Void,
        onResize: @escaping (Int, Int) -> Void
    ) {
        self.feed = feedHandle.feedStream
        self.feedHandle = feedHandle
        self.onUserBytes = onUserBytes
        self.onResize = onResize
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onUserBytes: onUserBytes, onResize: onResize)
    }

    public func makeUIView(context: Context) -> TerminalView {
        let term = TerminalView(frame: .zero)
        term.terminalDelegate = context.coordinator
        term.autocorrectionType = .no
        term.autocapitalizationType = .none
        term.smartDashesType = .no
        term.smartQuotesType = .no
        term.smartInsertDeleteType = .no
        term.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        context.coordinator.view = term

        // Pump PTY bytes into the terminal view from a background task.
        let stream = feed
        Task { @MainActor [weak term] in
            for await bytes in stream {
                term?.feed(byteArray: bytes[...])
            }
        }

        DispatchQueue.main.async { _ = term.becomeFirstResponder() }
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
