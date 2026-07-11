#if os(iOS)
import SwiftUI
import LancerCore

/// Read-only transcript for an observed host session, with Continue → LiveThread.
public struct ObservedSessionTranscriptView: View {
    @Environment(RelayFleetStore.self) private var relayFleetStore

    let row: RunningAgentsMapping.Row
    let onContinueInLancer: (String) -> Void

    @State private var messages: [SessionMessage] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isContinuePresented = false
    @State private var continuePrompt = ""
    @State private var continueError: String?

    public init(
        row: RunningAgentsMapping.Row,
        onContinueInLancer: @escaping (String) -> Void
    ) {
        self.row = row
        self.onContinueInLancer = onContinueInLancer
    }

    public var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading transcript…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                ContentUnavailableView(
                    "Couldn't load transcript",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if messages.isEmpty {
                ContentUnavailableView(
                    "No transcript yet",
                    systemImage: "text.alignleft",
                    description: Text("This session has no recorded turns on the host.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                            messageRow(message)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle(row.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Continue in Lancer") {
                    continuePrompt = ""
                    continueError = nil
                    isContinuePresented = true
                }
                .disabled(row.cwd.isEmpty || row.provider.isEmpty)
            }
        }
        .sheet(isPresented: $isContinuePresented) {
            continueSheet
        }
        .task(id: row.sessionId) {
            await loadTranscript()
        }
    }

    @ViewBuilder
    private func messageRow(_ message: SessionMessage) -> some View {
        switch message.role {
        case .user:
            Text(message.text)
                .font(.body)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        case .assistant:
            Text(message.text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .toolCall, .toolResult:
            VStack(alignment: .leading, spacing: 4) {
                if let toolName = message.toolName, !toolName.isEmpty {
                    Text(toolName)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(message.text)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        case .system, .unknown:
            Text(message.text)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var continueSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Follow-up prompt", text: $continuePrompt, axis: .vertical)
                        .lineLimit(3...8)
                } footer: {
                    Text("Sends into the exact \(row.providerLabel) session on the host, then opens a Lancer live thread.")
                }
                if let continueError {
                    Section {
                        Text(continueError)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Continue in Lancer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isContinuePresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        let trimmed = continuePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else {
                            continueError = "Enter a prompt to continue."
                            return
                        }
                        isContinuePresented = false
                        onContinueInLancer(trimmed)
                    }
                    .disabled(continuePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func loadTranscript() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        guard let machine = relayFleetStore.firstConnectedMachine else {
            loadError = "No connected machine."
            return
        }
        do {
            let result = try await machine.bridge.relayFetchTranscript(
                sessionId: row.sessionId,
                sinceLine: 0
            )
            messages = result.messages
        } catch {
            loadError = error.localizedDescription
        }
    }
}
#endif
