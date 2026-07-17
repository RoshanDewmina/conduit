#if os(iOS)
import SwiftUI

/// Settings sheet: feature request / bug report → push-backend `POST /feedback`.
public struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var feedbackType: FeedbackType = .feature
    @State private var message: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var didSucceed = false

    private let client: FeedbackClient

    public init(client: FeedbackClient = .makeDefault()) {
        self.client = client
    }

    private var canSend: Bool {
        FeedbackClient.isValidMessage(message.trimmingCharacters(in: .whitespacesAndNewlines))
            && !isSending
            && !didSucceed
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $feedbackType) {
                        ForEach(FeedbackType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("feedback.type")
                    .disabled(isSending || didSucceed)
                }

                Section {
                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("What should we know?")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $message)
                            .frame(minHeight: 160)
                            .accessibilityIdentifier("feedback.message")
                            .disabled(isSending || didSucceed)
                            .onChange(of: message) { _, _ in
                                if !didSucceed { errorMessage = nil }
                            }
                    }
                } footer: {
                    Text("Includes app version and device info")
                        .font(.footnote)
                }

                if let successMessage {
                    Section {
                        Text(successMessage)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("feedback.success")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("feedback.error")
                    }
                }
            }
            .navigationTitle("Send Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Send") {
                            Task { await send() }
                        }
                        .disabled(!canSend)
                        .accessibilityIdentifier("feedback.send")
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @MainActor
    private func send() async {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FeedbackClient.isValidMessage(trimmed) else { return }

        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            let result = try await client.submit(type: feedbackType, message: trimmed)
            didSucceed = true
            successMessage = "Thanks — filed as #\(result.issue)."
            try? await Task.sleep(for: .seconds(1.2))
            dismiss()
        } catch let error as FeedbackClientError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = FeedbackClientError.network.userMessage
        }
    }
}
#endif
