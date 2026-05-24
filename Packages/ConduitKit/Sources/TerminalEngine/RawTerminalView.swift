#if canImport(UIKit) && canImport(SwiftTerm)
import SwiftUI
import UIKit
import SwiftTerm
import ConduitCore

/// `UIViewRepresentable` host for SwiftTerm. Used in Raw mode (TUI programs
/// like vim, htop, tmux). The PTY byte stream is fed in via
/// `feedBytes(_:)`; user input flows back out via `onBytes(_:)`.
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

    public init(
        feed: AsyncStream<[UInt8]>,
        onUserBytes: @escaping (ArraySlice<UInt8>) -> Void,
        onResize: @escaping (Int, Int) -> Void
    ) {
        self.feed = feed
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
}
#endif
