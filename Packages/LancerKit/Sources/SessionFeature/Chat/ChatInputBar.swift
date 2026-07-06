#if os(iOS)
import SwiftUI
import PhotosUI
import LancerCore
import DesignSystem

// MARK: - Attachment type

public enum ComposerAttachment: Sendable {
    case photo(Data, UTType)
    case file(URL)
}


// MARK: - ChatInputBar

/// Pill-shaped chat input bar: text field, attachment, mic, snippet, send.
/// When `pendingApprovalCount > 0` an amber approval banner with Approve/Reject
/// appears above the input pill (feature flag: "flag.approvalBar").
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

    // (a) Approval quick-actions
    var pendingApprovalCount: Int = 0
    var onApprove: (() -> Void)? = nil
    var onReject: (() -> Void)? = nil

    // (b) Media attachment
    var onAttach: ((ComposerAttachment) -> Void)? = nil

    // P2.6: Keyboard toolbar rail
    var showKeyboardRail: Bool = true
    var onPaste: (() -> Void)? = nil
    var onInsertSnippet: (() -> Void)? = nil
    var onClearInput: (() -> Void)? = nil

    @AppStorage("flag.approvalBar")    private var approvalBarEnabled: Bool = true
    @AppStorage("flag.mediaAttachment") private var mediaAttachmentEnabled: Bool = true

    @State private var showAttachMenu = false
    @State private var photoPickerItem: PhotosPickerItem? = nil
    @State private var showFilePicker = false

    @Environment(\.lancerTokens) private var t

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
        liveInputActive: Binding<Bool>,
        pendingApprovalCount: Int = 0,
        onApprove: (() -> Void)? = nil,
        onReject: (() -> Void)? = nil,
        onAttach: ((ComposerAttachment) -> Void)? = nil,
        showKeyboardRail: Bool = true,
        onPaste: (() -> Void)? = nil,
        onInsertSnippet: (() -> Void)? = nil,
        onClearInput: (() -> Void)? = nil
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
        self.pendingApprovalCount = pendingApprovalCount
        self.onApprove = onApprove
        self.onReject = onReject
        self.onAttach = onAttach
        self.showKeyboardRail = showKeyboardRail
        self.onPaste = onPaste
        self.onInsertSnippet = onInsertSnippet
        self.onClearInput = onClearInput
    }

    public var body: some View {
        VStack(spacing: 0) {
            // (a) Approval quick-action banner — amber pill above input
            if approvalBarEnabled, pendingApprovalCount > 0, let approve = onApprove, let reject = onReject {
                DSApprovalBanner(count: pendingApprovalCount, onApprove: approve, onReject: reject)
            }

            // P2.6: Keyboard toolbar rail
            if showKeyboardRail, !isExecuting {
                keyboardToolbarRail
            }

            // Main input row
            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    pillField
                    actionButtons
                }
                if !isExecuting {
                    Text("⌘↵ to send")
                        .font(.dsMono(.caption2))
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
        // (b) Photo picker sheet
        .photosPicker(
            isPresented: $showAttachMenu,
            selection: $photoPickerItem,
            matching: .any(of: [.images, .screenshots])
        )
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let type: UTType = .jpeg
                    onAttach?(.photo(data, type))
                }
                photoPickerItem = nil
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                onAttach?(.file(url))
            }
        }
        .confirmationDialog("Attach to message", isPresented: $showAttachMenu) {
            // This block intentionally empty — photosPicker handles the picker;
            // the confirmationDialog below is used for camera + files choice.
        }
    }

    // MARK: - Pill text field

    private var pillField: some View {
        HStack(spacing: 6) {
            // Mode indicator
            if isExecuting {
                Image(systemName: "circle.fill")
                    .font(.dsMono(.caption2))
                    .foregroundStyle(t.ok)
                    .padding(.leading, 4)
            } else {
                Text(inputText.hasPrefix("#") ? "#" : "$")
                    .font(.dsMono(.footnote).weight(.medium))
                    .foregroundStyle(inputText.hasPrefix("#") ? t.accent : t.text3)
                    .padding(.leading, 4)
            }

            if isExecuting {
                Button {
                    liveInputActive = true
                } label: {
                    Text("Running — tap to type")
                        .font(.dsMono(.callout))
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
                Button {
                    onSendLiveKey([0x03])
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(t.danger)
                }
                .accessibilityLabel("Stop running command")
            } else {
                // (b) Attachment button
                if mediaAttachmentEnabled, onAttach != nil {
                    attachButton
                }
                // Mic
                Button(action: onMic) {
                    Image(systemName: isMicActive ? "mic.fill" : "mic")
                        .font(.title3)
                        .foregroundStyle(isMicActive ? t.danger : t.text3)
                }
                .accessibilityLabel(isMicActive ? "Stop dictation" : "Dictate")
                // Snippet
                Button(action: onSnippet) {
                    Image(systemName: "chevron.up.square")
                        .font(.title3)
                        .foregroundStyle(t.text3)
                }
                .accessibilityLabel("Insert snippet")
                // P2.7: Send button with long-press for advanced options
                Menu {
                    Button(action: onSubmit) {
                        Label("Send", systemImage: "arrow.up")
                    }
                    Button {
                        // Send as system command (# prefix)
                        inputText = "#\(inputText)"
                        onSubmit()
                    } label: {
                        Label("Send as system", systemImage: "terminal")
                    }
                    Button(action: onSnippet) {
                        Label("Insert snippet", systemImage: "chevron.up.square")
                    }
                    Button {
                        UIPasteboard.general.string = inputText
                    } label: {
                        Label("Copy to clipboard", systemImage: "doc.on.doc")
                    }
                    if inputText.count > 100 {
                        Button {
                            // Trim to last 100 chars
                            inputText = String(inputText.suffix(100))
                        } label: {
                            Label("Trim input", systemImage: "scissors")
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? t.text4 : t.accent
                        )
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Send message")
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Attachment button + menu

    private var attachButton: some View {
        Menu {
            Button {
                showAttachMenu = true
            } label: {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }
            Button {
                showFilePicker = true
            } label: {
                Label("Files", systemImage: "folder")
            }
        } label: {
            Image(systemName: "paperclip")
                .font(.title3)
                .foregroundStyle(t.text3)
        }
        .accessibilityLabel("Attach photo or file")
    }

    // MARK: - P2.6: Keyboard toolbar rail

    private var keyboardToolbarRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                railQuickAction(icon: "doc.on.clipboard", label: "Paste") {
                    onPaste?()
                }
                railQuickAction(icon: "chevron.up.square", label: "Snippet") {
                    onInsertSnippet?()
                }
                railQuickAction(icon: "arrow.uturn.backward", label: "Undo") {
                    onSendLiveKey([0x1b, 0x5b, 0x7a])  // Ctrl+Z
                }
                railQuickAction(icon: "xmark", label: "Clear") {
                    onClearInput?()
                }
                if !inputText.isEmpty {
                    railQuickAction(icon: "trash", label: "Clear") {
                        inputText = ""
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(t.surf1)
        .overlay(
            Rectangle().fill(t.border).frame(height: 0.5),
            alignment: .bottom
        )
    }

    private func railQuickAction(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.dsSans(.caption).weight(.medium))
                Text(label)
                    .font(.dsMonoPt(10))
            }
            .foregroundStyle(t.text2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(t.surf2)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

import UniformTypeIdentifiers

#endif
