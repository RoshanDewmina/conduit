#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem

// Pill-shaped chat input bar: text field, mic, snippet, send.
// Wraps the existing TerminalSafeTextField and LivePromptInputView.
// Shows live mode (keystroke passthrough) when vm.isExecutingUnified.
public struct ChatInputBar: View {
    @Binding var inputText: String
    let isExecuting: Bool
    let isTranslating: Bool
    let isDisconnected: Bool
    let onSubmit: () -> Void
    let onSnippet: () -> Void
    let onMic: () -> Void
    let isMicActive: Bool
    let onSendLiveKey: ([UInt8]) -> Void
    @Binding var liveInputActive: Bool

    @Environment(\.conduitTokens) private var t

    public init(
        inputText: Binding<String>,
        isExecuting: Bool,
        isTranslating: Bool,
        isDisconnected: Bool,
        onSubmit: @escaping () -> Void,
        onSnippet: @escaping () -> Void,
        onMic: @escaping () -> Void,
        isMicActive: Bool,
        onSendLiveKey: @escaping ([UInt8]) -> Void,
        liveInputActive: Binding<Bool>
    ) {
        self._inputText = inputText
        self.isExecuting = isExecuting
        self.isTranslating = isTranslating
        self.isDisconnected = isDisconnected
        self.onSubmit = onSubmit
        self.onSnippet = onSnippet
        self.onMic = onMic
        self.isMicActive = isMicActive
        self.onSendLiveKey = onSendLiveKey
        self._liveInputActive = liveInputActive
    }

    public var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                pillField
                actionButtons
            }
            if !isExecuting {
                Text("⌘↵ to send")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(t.text4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(t.surf1)
        .overlay(
            Rectangle().fill(t.surf3.opacity(0.5)).frame(height: 0.5),
            alignment: .top
        )
    }

    // MARK: - Pill text field

    private var pillField: some View {
        HStack(spacing: 6) {
            // Mode indicator
            if isExecuting {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(t.ok)
                    .padding(.leading, 4)
            } else {
                Text(inputText.hasPrefix("#") ? "#" : "$")
                    .font(.system(.footnote, design: .monospaced).weight(.medium))
                    .foregroundStyle(inputText.hasPrefix("#") ? t.accent : t.text3)
                    .padding(.leading, 4)
            }

            if isExecuting {
                // Live keystroke mode
                Button {
                    liveInputActive = true
                } label: {
                    Text("Running — tap to type")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(t.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                LivePromptInputView(isActive: $liveInputActive, onBytes: { bytes in
                    onSendLiveKey(Array(bytes))
                })
                .frame(width: 1, height: 1)
            } else {
                TerminalSafeTextField(
                    isTranslating ? "translating…" : "command",
                    text: $inputText,
                    isDisabled: isTranslating || isDisconnected,
                    autoFocus: true
                ) {
                    onSubmit()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background(t.surf2)
        .clipShape(RoundedRectangle(cornerRadius: t.radiusPill, style: .continuous))
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        HStack(spacing: 4) {
            if isExecuting {
                // Ctrl-C stop
                Button {
                    onSendLiveKey([0x03])
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(t.danger)
                }
            } else {
                // Mic
                Button(action: onMic) {
                    Image(systemName: isMicActive ? "mic.fill" : "mic")
                        .font(.title3)
                        .foregroundStyle(isMicActive ? t.danger : t.text3)
                }
                // Snippet
                Button(action: onSnippet) {
                    Image(systemName: "chevron.up.square")
                        .font(.title3)
                        .foregroundStyle(t.text3)
                }
                // Send
                Button(action: onSubmit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? t.text4 : t.accent
                        )
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

#endif
