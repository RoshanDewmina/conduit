import SwiftUI
import LancerCore

struct SnippetRunnerView: View {
    @Environment(WatchStore.self) private var store
    @State private var confirming: WatchSnippet?
    @State private var justRan: String?

    var body: some View {
        List {
            if store.snippets.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "text.quote")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("No snippets")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Add snippets in Lancer on iPhone.")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            } else {
                ForEach(store.snippets) { snippet in
                    Button {
                        confirming = snippet
                    } label: {
                        SnippetRowView(snippet: snippet, didRun: justRan == snippet.id)
                    }
                    .listRowBackground(
                        justRan == snippet.id
                            ? Color.green.opacity(0.15)
                            : Color(white: 0.12)
                    )
                }
            }
        }
        .listStyle(.carousel)
        .navigationTitle("Snippets")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            confirming?.name ?? "",
            isPresented: Binding(
                get: { confirming != nil },
                set: { if !$0 { confirming = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let snippet = confirming {
                Button("Run on server") {
                    store.runSnippet(snippet)
                    justRan = snippet.id
                    confirming = nil
                    // Clear the "just ran" indicator after 3s
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        await MainActor.run { self.justRan = nil }
                    }
                }
                Button("Cancel", role: .cancel) { confirming = nil }
            }
        } message: {
            if let snippet = confirming {
                Text(snippet.body)
                    .font(.system(.caption2, design: .monospaced))
            }
        }
    }
}

private struct SnippetRowView: View {
    let snippet: WatchSnippet
    let didRun: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(snippet.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if didRun {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "play.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(snippet.body)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}
