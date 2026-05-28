#if os(iOS)
import SwiftUI
import UIKit
import ConduitCore
import DesignSystem
import PersistenceKit

public struct SnippetEditorView: View {

    @State private var snippets: [Snippet] = []
    @State private var editingSnippet: Snippet? = nil
    @State private var isAddingNew = false
    private let repository: SnippetRepository?
    @Environment(\.conduitTokens) private var t

    public init(repository: SnippetRepository? = nil) {
        self.repository = repository
    }

    public var body: some View {
        List {
            ForEach(snippets) { snippet in
                Button {
                    editingSnippet = snippet
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snippet.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(t.text1)
                        Text(snippet.body)
                            .font(.caption.monospaced())
                            .foregroundStyle(t.text3)
                            .lineLimit(2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(t.surf1)
            }
            .onDelete { offsets in
                delete(at: offsets)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(t.surf0)
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
                save(updated)
            } onCancel: {
                // If this was a brand-new snippet (empty name/body), remove it
                if let idx = snippets.firstIndex(where: { $0.id == snippet.id }),
                   snippets[idx].name.isEmpty, snippets[idx].body.isEmpty {
                    snippets.remove(at: idx)
                }
                editingSnippet = nil
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let repository else { return }
        if let loaded = try? await repository.all() {
            snippets = loaded
        }
    }

    private func save(_ updated: Snippet) {
        if let idx = snippets.firstIndex(where: { $0.id == updated.id }) {
            snippets[idx] = updated
        } else {
            snippets.append(updated)
        }
        editingSnippet = nil

        guard let repository else { return }
        Task {
            try? await repository.upsert(updated)
        }
    }

    private func delete(at offsets: IndexSet) {
        let deleted = offsets.compactMap { index in
            snippets.indices.contains(index) ? snippets[index] : nil
        }
        snippets.remove(atOffsets: offsets)

        guard let repository else { return }
        Task {
            for snippet in deleted {
                try? await repository.delete(id: snippet.id)
            }
        }
    }
}

// MARK: - Edit sheet

private struct SnippetEditSheet: View {
    @State private var name: String
    @State private var commandBody: String
    @State private var arguments: [SnippetArgument]
    @State private var editingArgIndex: Int? = nil
    @State private var isAddingArg = false

    let originalID: SnippetID
    let originalCreatedAt: Date
    let originalUseCount: Int
    let onSave: (Snippet) -> Void
    let onCancel: () -> Void

    init(snippet: Snippet, onSave: @escaping (Snippet) -> Void, onCancel: @escaping () -> Void) {
        _name = State(initialValue: snippet.name)
        _commandBody = State(initialValue: snippet.body)
        _arguments = State(initialValue: snippet.arguments)
        originalID = snippet.id
        originalCreatedAt = snippet.createdAt
        originalUseCount = snippet.useCount
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
                    TerminalSafeTextView(
                        text: $commandBody,
                        font: .monospacedSystemFont(ofSize: 17, weight: .regular)
                    )
                    .frame(minHeight: 120)
                    Text("Use {{name}} placeholders to define parameters.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(arguments.indices, id: \.self) { i in
                        Button {
                            editingArgIndex = i
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(arguments[i].name).bold().foregroundStyle(.primary)
                                Text(arguments[i].sourceLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        arguments.remove(atOffsets: offsets)
                    }
                    Button {
                        isAddingArg = true
                    } label: {
                        Label("Add Parameter", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Parameters")
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
                            arguments: arguments,
                            useCount: originalUseCount,
                            createdAt: originalCreatedAt
                        ))
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                              || commandBody.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $isAddingArg) {
                ArgumentEditorSheet(argument: SnippetArgument(name: "")) { newArg in
                    arguments.append(newArg)
                    isAddingArg = false
                } onCancel: {
                    isAddingArg = false
                }
            }
            .sheet(item: Binding(
                get: { editingArgIndex.map { IdentifiableIndex(value: $0) } },
                set: { editingArgIndex = $0?.value }
            )) { idx in
                ArgumentEditorSheet(argument: arguments[idx.value]) { updated in
                    arguments[idx.value] = updated
                    editingArgIndex = nil
                } onCancel: {
                    editingArgIndex = nil
                }
            }
        }
    }
}

private struct IdentifiableIndex: Identifiable {
    let value: Int
    var id: Int { value }
}

// MARK: - Argument editor

private struct ArgumentEditorSheet: View {
    @State private var argName: String
    @State private var description: String
    @State private var defaultValue: String
    @State private var sourceType: SourceType
    @State private var enumRaw: String   // newline-separated enum values
    @State private var shellCommand: String

    let onSave: (SnippetArgument) -> Void
    let onCancel: () -> Void

    enum SourceType: String, CaseIterable, Identifiable {
        case literal = "Text input"
        case enumValues = "Fixed choices"
        case dynamicShell = "Shell command"
        var id: String { rawValue }
    }

    init(argument: SnippetArgument, onSave: @escaping (SnippetArgument) -> Void, onCancel: @escaping () -> Void) {
        _argName = State(initialValue: argument.name)
        _description = State(initialValue: argument.description ?? "")
        _defaultValue = State(initialValue: argument.defaultValue ?? "")
        self.onSave = onSave
        self.onCancel = onCancel
        switch argument.source {
        case .literal:
            _sourceType = State(initialValue: .literal)
            _enumRaw = State(initialValue: "")
            _shellCommand = State(initialValue: "")
        case .enumValues(let vals):
            _sourceType = State(initialValue: .enumValues)
            _enumRaw = State(initialValue: vals.joined(separator: "\n"))
            _shellCommand = State(initialValue: "")
        case .dynamicShellCommand(let cmd):
            _sourceType = State(initialValue: .dynamicShell)
            _enumRaw = State(initialValue: "")
            _shellCommand = State(initialValue: cmd)
        }
    }

    private var builtArgument: SnippetArgument {
        let source: SnippetArgument.Source
        switch sourceType {
        case .literal:
            source = .literal
        case .enumValues:
            let vals = enumRaw.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            source = .enumValues(vals)
        case .dynamicShell:
            source = .dynamicShellCommand(shellCommand.trimmingCharacters(in: .whitespaces))
        }
        return SnippetArgument(
            name: argName.trimmingCharacters(in: .whitespaces),
            description: description.isEmpty ? nil : description,
            defaultValue: defaultValue.isEmpty ? nil : defaultValue,
            source: source
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Parameter name") {
                    TextField("e.g. branch", text: $argName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Text("Use {{" + argName + "}} in the command body.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Input type") {
                    Picker("Type", selection: $sourceType) {
                        ForEach(SourceType.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    switch sourceType {
                    case .literal:
                        EmptyView()
                    case .enumValues:
                        VStack(alignment: .leading, spacing: 4) {
                            Text("One choice per line:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TerminalSafeTextView(
                                text: $enumRaw,
                                font: .monospacedSystemFont(ofSize: 15, weight: .regular)
                            )
                            .frame(minHeight: 80)
                        }
                    case .dynamicShell:
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Command run on the remote host:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("e.g. git branch --format='%(refname:short)'",
                                      text: $shellCommand)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .font(.caption.monospaced())
                        }
                    }
                }
                Section("Optional") {
                    TextField("Description", text: $description)
                    TextField("Default value", text: $defaultValue)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle(argName.isEmpty ? "New Parameter" : argName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(builtArgument)
                    }
                    .disabled(argName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

private extension SnippetArgument {
    var sourceLabel: String {
        switch source {
        case .literal: return "Text input"
        case .enumValues(let vals): return "\(vals.count) choice\(vals.count == 1 ? "" : "s")"
        case .dynamicShellCommand(let cmd): return "Shell: \(cmd)"
        }
    }
}
#endif
