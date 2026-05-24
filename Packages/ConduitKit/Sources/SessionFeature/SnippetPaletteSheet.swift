#if os(iOS)
import SwiftUI
import ConduitCore

public struct SnippetPaletteSheet: View {
    public let snippets: [Snippet]
    public let onInsert: (Snippet) -> Void
    public let onDismiss: () -> Void

    @State private var searchText: String = ""

    public init(
        snippets: [Snippet],
        onInsert: @escaping (Snippet) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.snippets = snippets
        self.onInsert = onInsert
        self.onDismiss = onDismiss
    }

    private var filtered: [Snippet] {
        guard !searchText.isEmpty else { return snippets }
        return snippets.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.body.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        NavigationStack {
            List(filtered, id: \.id) { snippet in
                Button {
                    onInsert(snippet)
                } label: {
                    VStack(alignment: .leading) {
                        Text(snippet.name)
                            .bold()
                        Text(snippet.body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .searchable(text: $searchText)
            .navigationTitle("Snippets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
            }
        }
    }
}
#endif
