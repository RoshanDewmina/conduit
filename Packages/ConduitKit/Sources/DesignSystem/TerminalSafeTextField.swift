#if os(iOS)
import SwiftUI
import UIKit

/// A `UIViewRepresentable` wrapping `UITextField` with every iOS
/// "smart text" transformation disabled.  Drop-in replacement for
/// SwiftUI `TextField` in any context where shell syntax must arrive
/// verbatim — prevents `--` → `—`, straight-quotes → curly-quotes, etc.
///
/// ## Smart features disabled
/// - `smartDashesType = .no`          — `--` stays `--`
/// - `smartQuotesType = .no`          — `'` / `"` stay straight
/// - `smartInsertDeleteType = .no`    — no smart space insertion
/// - `autocorrectionType = .no`       — no autocorrect
/// - `autocapitalizationType = .none` — no auto-caps
/// - `spellCheckingType = .no`        — no underlines
/// - `textContentType = .username`    — prevents password / email suggestion
///
/// Usage mirrors SwiftUI `TextField`:
/// ```swift
/// TerminalSafeTextField("command", text: $vm.inputText) {
///     Task { await vm.submit() }
/// }
/// ```
public struct TerminalSafeTextField: UIViewRepresentable {
    @Binding public var text: String
    public var placeholder: String
    public var font: UIFont
    public var returnKeyType: UIReturnKeyType
    public var isDisabled: Bool
    public var autoFocus: Bool
    public var onSubmit: (() -> Void)?

    public init(
        _ placeholder: String = "",
        text: Binding<String>,
        font: UIFont = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular),
        returnKeyType: UIReturnKeyType = .send,
        isDisabled: Bool = false,
        autoFocus: Bool = false,
        onSubmit: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.font = font
        self.returnKeyType = returnKeyType
        self.isDisabled = isDisabled
        self.autoFocus = autoFocus
        self.onSubmit = onSubmit
    }

    // MARK: - UIViewRepresentable

    public func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    public func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.delegate = context.coordinator

        // Disable every smart-text feature
        tf.smartDashesType        = .no
        tf.smartQuotesType        = .no
        tf.smartInsertDeleteType  = .no
        tf.autocorrectionType     = .no
        tf.autocapitalizationType = .none
        tf.spellCheckingType      = .no
        tf.textContentType        = .username  // suppresses password/email UI

        tf.font           = font
        tf.placeholder    = placeholder
        tf.returnKeyType  = returnKeyType
        tf.isEnabled      = !isDisabled
        tf.clearButtonMode = .never

        if autoFocus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                _ = tf.becomeFirstResponder()
            }
        }

        // Keep binding in sync on every edit
        tf.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textFieldEditingChanged(_:)),
            for: .editingChanged
        )
        return tf
    }

    public func updateUIView(_ tf: UITextField, context: Context) {
        // Push new value only when it actually changed to avoid losing
        // cursor position on every keystroke from SwiftUI re-renders.
        if tf.text != text {
            context.coordinator.isUpdatingFromBinding = true
            tf.text = text
            context.coordinator.isUpdatingFromBinding = false
        }
        if tf.placeholder  != placeholder   { tf.placeholder  = placeholder }
        if tf.font         != font          { tf.font         = font }
        if tf.returnKeyType != returnKeyType { tf.returnKeyType = returnKeyType }
        if tf.isEnabled    == isDisabled    { tf.isEnabled    = !isDisabled }
        context.coordinator.onSubmit = onSubmit
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var onSubmit: (() -> Void)?
        /// Guards against feedback loops between UITextField and the binding.
        var isUpdatingFromBinding = false

        init(text: Binding<String>, onSubmit: (() -> Void)?) {
            self._text = text
            self.onSubmit = onSubmit
        }

        @objc func textFieldEditingChanged(_ tf: UITextField) {
            guard !isUpdatingFromBinding else { return }
            let new = tf.text ?? ""
            if text != new { text = new }
        }

        public func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            onSubmit?()
            return false  // caller decides whether to resign
        }

        // Keep binding in sync when selection changes (paste, cut, etc.)
        public func textFieldDidChangeSelection(_ tf: UITextField) {
            guard !isUpdatingFromBinding else { return }
            let new = tf.text ?? ""
            if text != new { text = new }
        }
    }
}

public struct TerminalSafeTextView: UIViewRepresentable {
    @Binding public var text: String
    public var font: UIFont
    public var isDisabled: Bool

    public init(
        text: Binding<String>,
        font: UIFont = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular),
        isDisabled: Bool = false
    ) {
        self._text = text
        self.font = font
        self.isDisabled = isDisabled
    }

    public func makeCoordinator() -> TextViewCoordinator {
        TextViewCoordinator(text: $text)
    }

    public func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.smartDashesType = .no
        tv.smartQuotesType = .no
        tv.smartInsertDeleteType = .no
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.spellCheckingType = .no
        tv.textContentType = .username
        tv.font = font
        tv.backgroundColor = .clear
        tv.isScrollEnabled = true
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        tv.isEditable = !isDisabled
        return tv
    }

    public func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            context.coordinator.isUpdatingFromBinding = true
            tv.text = text
            context.coordinator.isUpdatingFromBinding = false
        }
        if tv.font != font { tv.font = font }
        if tv.isEditable == isDisabled { tv.isEditable = !isDisabled }
    }

    public final class TextViewCoordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        var isUpdatingFromBinding = false

        init(text: Binding<String>) {
            self._text = text
        }

        public func textViewDidChange(_ textView: UITextView) {
            guard !isUpdatingFromBinding else { return }
            let new = textView.text ?? ""
            if text != new { text = new }
        }
    }
}
#endif
