#if os(iOS)
import SwiftUI
import ConduitCore

public struct SnippetEditorView: View {

    @State private var snippets: [Snippet] = []
    @State private var editingSnippet: Snippet? = nil
    @State private var isAddingNew = false

    public init() {}

    public var body: some View {
        List {
            ForEach(snippets) { snippet in
                Button {
                    editingSnippet = snippet
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snippet.name).bold().foregroundStyle(.primary)
                        Text(snippet.body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                snippets.remove(atOffsets: offsets)
            }
        }
        .navigationTitle("Snippets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let fresh = Snippet(name: "", body: "")
                    snippets.append(fresh)
                    editingSnippet = fresh
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditSheet(snippet: snippet) { updated in
                if let idx = snippets.firstIndex(where: { $0.id == updated.id }) {
                    snippets[idx] = updated
                } else {
                    snippets.append(updated)
                }
                editingSnippet = nil
            } onCancel: {
                // If this was a brand-new snippet (empty name/body), remove it
                if let idx = snippets.firstIndex(where: { $0.id == snippet.id }),
                   snippets[idx].name.isEmpty, snippets[idx].body.isEmpty {
                    snippets.remove(at: idx)
                }
                editingSnippet = nil
            }
        }
    }
}

// MARK: - Edit sheet

private struct SnippetEditSheet: View {
    @State private var name: String
    @State private var commandBody: String

    let originalID: SnippetID
    let originalCreatedAt: Date
    let onSave: (Snippet) -> Void
    let onCancel: () -> Void

    init(snippet: Snippet, onSave: @escaping (Snippet) -> Void, onCancel: @escaping () -> Void) {
        _name = State(initialValue: snippet.name)
        _commandBody = State(initialValue: snippet.body)
        originalID = snippet.id
        originalCreatedAt = snippet.createdAt
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. tail logs", text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("Command body") {
                    TextEditor(text: $commandBody)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle(name.isEmpty ? "New Snippet" : name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(Snippet(
                            id: originalID,
                            name: name,
                            body: commandBody,
                            createdAt: originalCreatedAt
                        ))
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                              || commandBody.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
#endif
