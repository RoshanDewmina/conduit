#if os(iOS)
import SwiftUI
import ConduitCore

public struct SnippetPaletteSheet: View {
    public let snippets: [Snippet]
    /// Called with the final body string (arguments already substituted).
    public let onInsert: (Snippet, String) -> Void
    public let onDismiss: () -> Void
    /// Optional: runs a shell command on the remote and returns stdout.
    public let executeShellCommand: ((String) async -> String)?

    @State private var searchText: String = ""
    @State private var fillingSnippet: Snippet? = nil

    public init(
        snippets: [Snippet],
        onInsert: @escaping (Snippet, String) -> Void,
        onDismiss: @escaping () -> Void,
        executeShellCommand: ((String) async -> String)? = nil
    ) {
        self.snippets = snippets
        self.onInsert = onInsert
        self.onDismiss = onDismiss
        self.executeShellCommand = executeShellCommand
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
                    if snippet.arguments.isEmpty {
                        onInsert(snippet, snippet.body)
                    } else {
                        fillingSnippet = snippet
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snippet.name)
                            .bold()
                        Text(snippet.body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if !snippet.arguments.isEmpty {
                            Label("\(snippet.arguments.count) parameter\(snippet.arguments.count == 1 ? "" : "s")",
                                  systemImage: "slider.horizontal.3")
                                .font(.caption2)
                                .foregroundStyle(.tint)
                        }
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
            .sheet(item: $fillingSnippet) { snippet in
                ArgumentFillSheet(
                    snippet: snippet,
                    executeShellCommand: executeShellCommand
                ) { filledBody in
                    fillingSnippet = nil
                    onInsert(snippet, filledBody)
                } onCancel: {
                    fillingSnippet = nil
                }
            }
        }
    }
}

// MARK: - Argument fill form

private struct ArgumentFillSheet: View {
    let snippet: Snippet
    let executeShellCommand: ((String) async -> String)?
    let onInsert: (String) -> Void
    let onCancel: () -> Void

    @State private var values: [String: String] = [:]
    @State private var dynamicOptions: [String: [String]] = [:]
    @State private var loadingArgs: Set<String> = []

    private var filledBody: String {
        var result = snippet.body
        for arg in snippet.arguments {
            let placeholder = "{{\(arg.name)}}"
            let value = values[arg.name] ?? arg.defaultValue ?? ""
            result = result.replacingOccurrences(of: placeholder, with: value)
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(snippet.body)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Command")
                }

                ForEach(snippet.arguments, id: \.name) { arg in
                    Section {
                        argumentField(for: arg)
                    } header: {
                        Text(arg.name)
                    } footer: {
                        if let desc = arg.description {
                            Text(desc)
                        }
                    }
                }

                Section {
                    Text(filledBody)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                } header: {
                    Text("Preview")
                }
            }
            .navigationTitle(snippet.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert") {
                        onInsert(filledBody)
                    }
                }
            }
            .task {
                for arg in snippet.arguments {
                    if case .dynamicShellCommand(let cmd) = arg.source {
                        await loadDynamicOptions(arg: arg, command: cmd)
                    }
                    if values[arg.name] == nil {
                        values[arg.name] = arg.defaultValue ?? ""
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func argumentField(for arg: SnippetArgument) -> some View {
        switch arg.source {
        case .literal:
            TextField(arg.defaultValue ?? "value", text: Binding(
                get: { values[arg.name] ?? arg.defaultValue ?? "" },
                set: { values[arg.name] = $0 }
            ))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

        case .enumValues(let options):
            Picker(arg.name, selection: Binding(
                get: { values[arg.name] ?? options.first ?? "" },
                set: { values[arg.name] = $0 }
            )) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .onAppear {
                if values[arg.name] == nil {
                    values[arg.name] = arg.defaultValue ?? options.first ?? ""
                }
            }

        case .dynamicShellCommand:
            let opts = dynamicOptions[arg.name] ?? []
            if loadingArgs.contains(arg.name) {
                HStack {
                    ProgressView()
                    Text("Loading options…").foregroundStyle(.secondary)
                }
            } else if opts.isEmpty {
                TextField(arg.defaultValue ?? "value", text: Binding(
                    get: { values[arg.name] ?? arg.defaultValue ?? "" },
                    set: { values[arg.name] = $0 }
                ))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            } else {
                Picker(arg.name, selection: Binding(
                    get: { values[arg.name] ?? opts.first ?? "" },
                    set: { values[arg.name] = $0 }
                )) {
                    ForEach(opts, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .onAppear {
                    if values[arg.name] == nil {
                        values[arg.name] = arg.defaultValue ?? opts.first ?? ""
                    }
                }
            }
        }
    }

    private func loadDynamicOptions(arg: SnippetArgument, command: String) async {
        guard let exec = executeShellCommand else { return }
        loadingArgs.insert(arg.name)
        let raw = await exec(command)
        let lines = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        dynamicOptions[arg.name] = lines
        loadingArgs.remove(arg.name)
        if values[arg.name] == nil {
            values[arg.name] = arg.defaultValue ?? lines.first ?? ""
        }
    }
}
#endif
