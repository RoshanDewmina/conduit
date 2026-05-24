#if os(iOS)
import SwiftUI
import AgentKit

/// A standalone sheet that streams an AI explanation for a failed command.
/// Replaces the inline `explainSheet` helper in `SessionView`; SessionViewModel
/// should wire this via `PromptBuilder.explainError(...)`.
public struct ExplainSheet: View {
    public let command: String
    public let output: String
    public let exitCode: Int
    public let report: RedactionReport
    public let onDismiss: () -> Void

    @State private var explanation: String = ""
    @State private var isStreaming: Bool = false

    public init(
        command: String,
        output: String,
        exitCode: Int,
        report: RedactionReport,
        onDismiss: @escaping () -> Void
    ) {
        self.command = command
        self.output = output
        self.exitCode = exitCode
        self.report = report
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // Command section
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Command")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(command)
                            .font(.system(.body, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.tertiary.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Exit code
                    Text("Exit code \(exitCode)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Redaction pill
                    if report.redactedCount > 0 {
                        Label("Redacted: \(report.redactedCount) item\(report.redactedCount == 1 ? "" : "s")",
                              systemImage: "eye.slash.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }

                    Divider()

                    // AI explanation
                    HStack {
                        Image(systemName: "sparkles").foregroundStyle(.tint)
                        Text("AI explanation").font(.headline)
                        Spacer()
                        if isStreaming {
                            ProgressView().scaleEffect(0.7)
                        }
                    }

                    Text(explanation.isEmpty ? "Generating explanation…" : explanation)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.default, value: explanation)
                }
                .padding()
            }
            .navigationTitle("Explain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss", action: onDismiss)
                }
            }
        }
    }
}

#endif
