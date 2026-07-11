#if os(iOS)
import SwiftUI
import LancerCore

/// Docked composer via `.safeAreaInset` — never a full-screen sheet.
/// Ported from stablyai/orca (MIT) NativeChatView.tsx flex-1 / shrink-0 column.
public struct CursorDockedComposer: View {
    public struct RunTargetOption: Identifiable, Sendable, Equatable {
        public let id: String
        public let title: String
        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    public struct ModelOption: Identifiable, Sendable, Equatable {
        public let id: String
        public let title: String
        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    @FocusState private var isFocused: Bool
    @State private var text: String = ""

    private let placeholder: String
    private let draftKey: String?
    private let cwdResolution: CursorComposerCWDResolution.Resolution
    private let runTargetOptions: [RunTargetOption]
    private let selectedRunTargetID: String?
    private let modelOptions: [ModelOption]
    private let selectedModelID: String?
    private let prefillText: String?
    private let isWorking: Bool
    private let onPickRunTarget: (String) -> Void
    private let onPickModel: (String) -> Void
    private let onSend: (String) -> Void

    public init(
        placeholder: String = "Plan, ask, build...",
        draftKey: String? = nil,
        cwdResolution: CursorComposerCWDResolution.Resolution = .init(path: "~", blocked: false, message: nil),
        runTargetOptions: [RunTargetOption] = [],
        selectedRunTargetID: String? = nil,
        modelOptions: [ModelOption] = [],
        selectedModelID: String? = nil,
        prefillText: String? = nil,
        isWorking: Bool = false,
        onPickRunTarget: @escaping (String) -> Void = { _ in },
        onPickModel: @escaping (String) -> Void = { _ in },
        onSend: @escaping (String) -> Void
    ) {
        self.placeholder = placeholder
        self.draftKey = draftKey
        self.cwdResolution = cwdResolution
        self.runTargetOptions = runTargetOptions
        self.selectedRunTargetID = selectedRunTargetID
        self.modelOptions = modelOptions
        self.selectedModelID = selectedModelID
        self.prefillText = prefillText
        self.isWorking = isWorking
        self.onPickRunTarget = onPickRunTarget
        self.onPickModel = onPickModel
        self.onSend = onSend
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !cwdResolution.blocked
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = cwdResolution.message, cwdResolution.blocked {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("composer.cwd-warning")
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($isFocused)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("composer.text-field")

                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(!canSend)
                .accessibilityIdentifier("composer.send")
            }

            HStack(spacing: 12) {
                if !runTargetOptions.isEmpty {
                    Menu {
                        ForEach(runTargetOptions) { option in
                            Button(option.title) { onPickRunTarget(option.id) }
                        }
                    } label: {
                        Label(
                            runTargetOptions.first(where: { $0.id == selectedRunTargetID })?.title ?? "Run on",
                            systemImage: "desktopcomputer"
                        )
                        .font(.caption)
                    }
                    .accessibilityIdentifier("composer.run-target-menu")
                }
                if !modelOptions.isEmpty {
                    Menu {
                        ForEach(modelOptions) { option in
                            Button(option.title) { onPickModel(option.id) }
                        }
                    } label: {
                        Text(modelOptions.first(where: { $0.id == selectedModelID })?.title ?? "Model")
                            .font(.caption)
                    }
                    .accessibilityIdentifier("composer.model-menu")
                }
                if isWorking {
                    ProgressView().controlSize(.mini)
                    Text("Working…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .background(.bar)
        .onAppear {
            if let prefillText, !prefillText.isEmpty {
                text = prefillText
            } else if let draftKey {
                let draft = CursorComposerDraftStore.shared.loadDraft(threadID: draftKey)
                if !draft.isEmpty { text = draft }
            }
        }
        .onChange(of: text) { _, newValue in
            guard let draftKey else { return }
            if newValue.isEmpty {
                CursorComposerDraftStore.shared.clearDraft(threadID: draftKey)
            } else {
                CursorComposerDraftStore.shared.saveDraft(threadID: draftKey, text: newValue)
            }
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !cwdResolution.blocked else { return }
        if let draftKey {
            CursorComposerDraftStore.shared.clearDraft(threadID: draftKey)
        }
        text = ""
        onSend(trimmed)
    }
}
#endif
