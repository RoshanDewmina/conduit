#if os(iOS)
import SwiftUI

/// Sheet opened from `BackgroundTasksPill`: Running (title / type / elapsed)
/// and Finished N (title / type / Completed).
///
/// Stop is omitted — there is no per-tool cancel on the live bridge /
/// `RunControlIntents` / daemon RPC surface (only run-level `agent.cancel`).
struct BackgroundTasksSheet: View {
    let rows: [BackgroundTasksPresentation.TaskRow]
    @Environment(\.dismiss) private var dismiss

    private var running: [BackgroundTasksPresentation.TaskRow] {
        BackgroundTasksPresentation.running(in: rows)
    }

    private var finished: [BackgroundTasksPresentation.TaskRow] {
        BackgroundTasksPresentation.finished(in: rows)
    }

    var body: some View {
        NavigationStack {
            List {
                if !running.isEmpty {
                    Section("Running") {
                        ForEach(running) { row in
                            runningRow(row)
                        }
                    }
                }

                if !finished.isEmpty {
                    Section("Finished \(finished.count)") {
                        ForEach(finished) { row in
                            finishedRow(row)
                        }
                    }
                }

                if running.isEmpty && finished.isEmpty {
                    Text("No background tasks")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Background tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("background-tasks-sheet")
    }

    private func runningRow(_ row: BackgroundTasksPresentation.TaskRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: typeIcon(row.typeLabel))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(row.typeLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let elapsed = BackgroundTasksPresentation.elapsedLabel(
                            startedAt: row.startedAt,
                            now: context.date
                        ) {
                            Text("·")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                            Text(elapsed)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            ProgressView()
                .controlSize(.mini)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(runningAccessibilityLabel(row)))
    }

    private func finishedRow(_ row: BackgroundTasksPresentation.TaskRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: typeIcon(row.typeLabel))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(row.typeLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text("Completed")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(row.title), \(row.typeLabel), Completed"))
    }

    private func typeIcon(_ typeLabel: String) -> String {
        switch typeLabel.lowercased() {
        case "shell": return "terminal"
        case "read": return "doc.text"
        case "edit", "write": return "pencil"
        default: return "wrench.and.screwdriver"
        }
    }

    private func runningAccessibilityLabel(_ row: BackgroundTasksPresentation.TaskRow) -> String {
        var parts = [row.title, row.typeLabel]
        if let startedAt = row.startedAt,
           let elapsed = BackgroundTasksPresentation.elapsedLabel(startedAt: startedAt, now: .now) {
            parts.append(elapsed)
        }
        return parts.joined(separator: ", ")
    }
}
#endif
