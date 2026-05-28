#if os(iOS)
import SwiftUI
import UIKit

/// A `UIViewRepresentable` transparent responder that captures every
/// keystroke from the software (or hardware) keyboard and forwards it
/// directly to the PTY — no buffering, no intermediate text field.
///
/// This is the iOS equivalent of cmux's `ghostty_surface_key()` direct
/// call.  It is shown in place of the composer `TextField` whenever the
/// active block is in the `.executing` state, so interactive TUI programs
/// (Claude Code, top, vim without alt-screen, any interactive REPL) receive
/// each character as the user presses it.
///
/// Visual feedback comes from the PTY's own echo — the program writes
/// back what the user typed, and that output flows into the active block
/// via `onBlockBytes` as usual.
public struct LivePromptInputView: UIViewRepresentable {
    /// Raw PTY bytes delivered on every keystroke.
    public var onBytes: ([UInt8]) -> Void
    /// Binding that triggers `becomeFirstResponder()` when flipped to `true`.
    /// The view resets it back to `false` after attempting to become responder
    /// so the binding can be set again for subsequent activations.
    @Binding public var isActive: Bool

    public init(isActive: Binding<Bool>, onBytes: @escaping ([UInt8]) -> Void) {
        self._isActive = isActive
        self.onBytes = onBytes
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onBytes: onBytes)
    }

    public func makeUIView(context: Context) -> LiveInputUIView {
        let v = LiveInputUIView()
        v.onBytes = { [weak coordinator = context.coordinator] bytes in
            coordinator?.onBytes(bytes)
        }
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = true
        return v
    }

    public func updateUIView(_ v: LiveInputUIView, context: Context) {
        context.coordinator.onBytes = onBytes
        v.onBytes = { [weak coordinator = context.coordinator] bytes in
            coordinator?.onBytes(bytes)
        }
        if isActive, !v.isFirstResponder {
            // Use asyncAfter so SwiftUI has committed the layout before
            // we request first responder — avoids the race where the view
            // isn't in the window hierarchy yet.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                _ = v.becomeFirstResponder()
            }
            // Reset so the binding can be set again for subsequent taps.
            DispatchQueue.main.async { isActive = false }
        }
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject {
        var onBytes: ([UInt8]) -> Void
        init(onBytes: @escaping ([UInt8]) -> Void) { self.onBytes = onBytes }
    }
}

// MARK: - Underlying UIKit view

/// A zero-size transparent `UIView` that conforms to `UIKeyInput` so it
/// can become first responder and absorb software-keyboard input.
///
/// Every `insertText` / `deleteBackward` call is translated to PTY bytes
/// immediately.  No text is retained in the view itself.
public final class LiveInputUIView: UIView {
    var onBytes: (([UInt8]) -> Void)?

    public override var canBecomeFirstResponder: Bool { true }
    public override var canResignFirstResponder: Bool { true }
    public override var textInputContextIdentifier: String? { "conduit.live-input" }

    public var autocorrectionType: UITextAutocorrectionType = .no
    public var autocapitalizationType: UITextAutocapitalizationType = .none
    public var spellCheckingType: UITextSpellCheckingType = .no
    public var smartDashesType: UITextSmartDashesType = .no
    public var smartQuotesType: UITextSmartQuotesType = .no
    public var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    public var returnKeyType: UIReturnKeyType = .send
    public var keyboardType: UIKeyboardType = .default
    public var textContentType: UITextContentType? = .username
}

// MARK: UIKeyInput conformance

extension LiveInputUIView: UIKeyInput {
    public var hasText: Bool { false }

    /// Called by the system for every character key press.
    /// Maps Return → CR (\r) and forwards everything else verbatim.
    public func insertText(_ text: String) {
        guard let cb = onBytes else { return }
        switch text {
        case "\n": cb([0x0d])          // Return → CR
        default:   cb(Array(text.utf8))
        }
    }

    /// Called when the user presses Backspace / Delete.
    /// Sends ANSI DEL (0x7f) to the PTY.
    public func deleteBackward() {
        onBytes?([0x7f])
    }
}

extension LiveInputUIView: UITextInputTraits {}
#endif
