#if os(iOS)
import SwiftUI
import UIKit
import ConduitCore
import DesignSystem
import PersistenceKit

public struct SnippetEditorView: View {

    @State private var snippets: [Snippet] = []
    @State private var editingSnippet: Snippet? = nil
    private let repository: SnippetRepository?
    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss

    public init(repository: SnippetRepository? = nil) {
        self.repository = repository
    }

    public var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                DSDetailHeader("snippets", onBack: { dismiss() }) {
                    DSIconButton(.plus) {
                        let fresh = Snippet(name: "", body: "")
                        snippets.append(fresh)
                        editingSnippet = fresh
                    }
                }

                if snippets.isEmpty {
                    Spacer()
                    DSEmptyState(
                        dotMatrix: .idle,
                        title: "no snippets yet",
                        subtitle: "Save reusable commands with {{parameters}} you can fill in before running.",
                        action: ("new snippet", {
                            let fresh = Snippet(name: "", body: "")
                            snippets.append(fresh)
                            editingSnippet = fresh
                        })
                    )
                    .padding(.horizontal, 24)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(snippets) { snippet in
                                snippetRow(snippet)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditSheet(snippet: snippet) { updated in
                save(updated)
            } onCancel: {
                if let idx = snippets.firstIndex(where: { $0.id == snippet.id }),
                   snippets[idx].name.isEmpty, snippets[idx].body.isEmpty {
                    snippets.remove(at: idx)
                }
                editingSnippet = nil
            }
        }
        .task { await load() }
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        Button { editingSnippet = snippet } label: {
            HStack(alignment: .top, spacing: 10) {
                DSIconView(.list, size: 14, color: t.text3).padding(.top, 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(snippet.name.isEmpty ? "untitled" : snippet.name)
                        .font(.dsMonoPt(13, weight: .medium))
                        .foregroundStyle(t.text)
                    Text(snippet.body)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                DSIconView(.chevronRight, size: 13, color: t.text4).padding(.top, 3)
            }
            .padding(13)
            .contentShape(Rectangle())
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { delete(snippet) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
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
        Task { try? await repository.upsert(updated) }
    }

    private func delete(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
        guard let repository else { return }
        Task { try? await repository.delete(id: snippet.id) }
    }
}

// MARK: - Edit sheet

private struct SnippetEditSheet: View {
    @State private var name: String
    @State private var commandBody: String
    @State private var hostTagsRaw: String
    @State private var tagsRaw: String
    @State private var arguments: [SnippetArgument]
    @State private var editingArgIndex: Int? = nil
    @State private var isAddingArg = false

    let originalID: SnippetID
    let originalCreatedAt: Date
    let originalUseCount: Int
    let onSave: (Snippet) -> Void
    let onCancel: () -> Void

    @Environment(\.conduitTokens) private var t

    init(snippet: Snippet, onSave: @escaping (Snippet) -> Void, onCancel: @escaping () -> Void) {
        _name = State(initialValue: snippet.name)
        _commandBody = State(initialValue: snippet.body)
        _hostTagsRaw = State(initialValue: snippet.hostTags.joined(separator: ", "))
        _tagsRaw = State(initialValue: snippet.tags.joined(separator: ", "))
        _arguments = State(initialValue: snippet.arguments)
        originalID = snippet.id
        originalCreatedAt = snippet.createdAt
        originalUseCount = snippet.useCount
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && !commandBody.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader(name.isEmpty ? "new snippet" : name, onBack: onCancel) {
                    Button {
                        onSave(Snippet(
                            id: originalID, name: name, body: commandBody,
                            arguments: arguments, useCount: originalUseCount,
                            createdAt: originalCreatedAt
                        ))
                    } label: {
                        Text("save")
                            .font(.dsDisplayPt(12, weight: .semibold))
                            .foregroundStyle(isValid ? t.accentFg : t.text3)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(isValid ? t.accent : t.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isValid)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        BlocksField(label: "NAME", placeholder: "e.g. tail logs", text: $name, mono: false, tokens: t)

                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("COMMAND BODY")
                            TerminalSafeTextView(text: $commandBody,
                                                 font: UIFont(name: "FiraCode-Regular", size: 14)
                                                    ?? .monospacedSystemFont(ofSize: 14, weight: .regular))
                                .frame(minHeight: 120)
                                .padding(10)
                                .background(t.surfaceSunk)
                                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                                    .strokeBorder(t.border, lineWidth: 1))
                            Text("Use {{name}} placeholders to define parameters.")
                                .font(.dsMonoPt(11)).foregroundStyle(t.text3)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("PARAMETERS")
                            VStack(spacing: 0) {
                                ForEach(arguments.indices, id: \.self) { i in
                                    Button { editingArgIndex = i } label: {
                                        HStack(spacing: 8) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(arguments[i].name)
                                                    .font(.dsMonoPt(13, weight: .medium)).foregroundStyle(t.text)
                                                Text(arguments[i].sourceLabel)
                                                    .font(.dsMonoPt(11)).foregroundStyle(t.text3)
                                            }
                                            Spacer()
                                            DSIconView(.chevronRight, size: 12, color: t.text4)
                                        }
                                        .padding(.horizontal, 13).padding(.vertical, 11)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) { arguments.remove(at: i) } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    DSDivider(.soft)
                                }
                                Button { isAddingArg = true } label: {
                                    HStack(spacing: 8) {
                                        DSIconView(.plus, size: 13, color: t.accent)
                                        Text("add parameter").font(.dsMonoPt(13)).foregroundStyle(t.accent)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 13).padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            .background(t.surface)
                            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                                .strokeBorder(t.border, lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
                }
            }
        }
        .sheet(isPresented: $isAddingArg) {
            ArgumentEditorSheet(argument: SnippetArgument(name: "")) { newArg in
                arguments.append(newArg); isAddingArg = false
            } onCancel: { isAddingArg = false }
        }
        .sheet(item: Binding(
            get: { editingArgIndex.map { IdentifiableIndex(value: $0) } },
            set: { editingArgIndex = $0?.value }
        )) { idx in
            ArgumentEditorSheet(argument: arguments[idx.value]) { updated in
                arguments[idx.value] = updated; editingArgIndex = nil
            } onCancel: { editingArgIndex = nil }
        }
    }

    private func fieldLabel(_ s: String) -> some View {
        Text(s).font(.dsDisplayPt(10, weight: .semibold)).tracking(10 * 0.08).foregroundStyle(t.text3)
    }

    private func parseTags(_ raw: String) -> [String] {
        Array(Set(
            raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )).sorted()
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
    @State private var enumRaw: String
    @State private var shellCommand: String

    let onSave: (SnippetArgument) -> Void
    let onCancel: () -> Void

    @Environment(\.conduitTokens) private var t

    enum SourceType: String, CaseIterable, Identifiable, Hashable, Sendable {
        case literal = "Text input"
        case enumValues = "Fixed choices"
        case dynamicShell = "Shell command"
        var id: String { rawValue }
        var shortLabel: String {
            switch self {
            case .literal: return "text"
            case .enumValues: return "choices"
            case .dynamicShell: return "shell"
            }
        }
    }

    init(argument: SnippetArgument, onSave: @escaping (SnippetArgument) -> Void, onCancel: @escaping () -> Void) {
        _argName = State(initialValue: argument.name)
        _description = State(initialValue: argument.description ?? "")
        _defaultValue = State(initialValue: argument.defaultValue ?? "")
        self.onSave = onSave
        self.onCancel = onCancel
        switch argument.source {
        case .literal:
            _sourceType = State(initialValue: .literal); _enumRaw = State(initialValue: ""); _shellCommand = State(initialValue: "")
        case .enumValues(let vals):
            _sourceType = State(initialValue: .enumValues); _enumRaw = State(initialValue: vals.joined(separator: "\n")); _shellCommand = State(initialValue: "")
        case .dynamicShellCommand(let cmd):
            _sourceType = State(initialValue: .dynamicShell); _enumRaw = State(initialValue: ""); _shellCommand = State(initialValue: cmd)
        }
    }

    private var builtArgument: SnippetArgument {
        let source: SnippetArgument.Source
        switch sourceType {
        case .literal:
            source = .literal
        case .enumValues:
            let vals = enumRaw.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
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

    private var isValid: Bool { !argName.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader(argName.isEmpty ? "new parameter" : argName, onBack: onCancel) {
                    Button { onSave(builtArgument) } label: {
                        Text("done")
                            .font(.dsDisplayPt(12, weight: .semibold))
                            .foregroundStyle(isValid ? t.accentFg : t.text3)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(isValid ? t.accent : t.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isValid)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            BlocksField(label: "PARAMETER NAME", placeholder: "e.g. branch", text: $argName, mono: true, tokens: t)
                            Text("Use {{" + argName + "}} in the command body.")
                                .font(.dsMonoPt(11)).foregroundStyle(t.text3)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("INPUT TYPE")
                            DSSegmentedPicker(
                                options: SourceType.allCases.map { (label: $0.shortLabel, value: $0) },
                                selection: $sourceType
                            )
                            switch sourceType {
                            case .literal:
                                EmptyView()
                            case .enumValues:
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("One choice per line:").font(.dsMonoPt(11)).foregroundStyle(t.text3)
                                    TerminalSafeTextView(text: $enumRaw,
                                                         font: UIFont(name: "FiraCode-Regular", size: 14) ?? .monospacedSystemFont(ofSize: 14, weight: .regular))
                                        .frame(minHeight: 80)
                                        .padding(10).background(t.surfaceSunk)
                                        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: t.r3, style: .continuous).strokeBorder(t.border, lineWidth: 1))
                                }
                            case .dynamicShell:
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Command run on the remote host:").font(.dsMonoPt(11)).foregroundStyle(t.text3)
                                    BlocksField(label: nil, placeholder: "git branch --format='%(refname:short)'", text: $shellCommand, mono: true, tokens: t)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel("OPTIONAL")
                            BlocksField(label: nil, placeholder: "Description", text: $description, mono: false, tokens: t)
                            BlocksField(label: nil, placeholder: "Default value", text: $defaultValue, mono: true, tokens: t)
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
                }
            }
        }
    }

    private func fieldLabel(_ s: String) -> some View {
        Text(s).font(.dsDisplayPt(10, weight: .semibold)).tracking(10 * 0.08).foregroundStyle(t.text3)
    }
}

// MARK: - BLOCKS field (uppercase label + square bordered input, blue focus + $ prefix for mono)

private struct BlocksField: View {
    let label: String?
    let placeholder: String
    @Binding var text: String
    let mono: Bool
    let tokens: ConduitTokens
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                Text(label.uppercased())
                    .font(.dsDisplayPt(10, weight: .semibold)).tracking(10 * 0.08)
                    .foregroundStyle(tokens.text3)
            }
            HStack(spacing: 8) {
                if mono {
                    Text("$").font(.dsMonoPt(13, weight: .medium)).foregroundStyle(tokens.accent)
                }
                TextField(placeholder, text: $text)
                    .font(mono ? .dsMonoPt(13) : .dsSansPt(13))
                    .foregroundStyle(tokens.text)
                    .tint(tokens.accent)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(tokens.surfaceSunk)
            .clipShape(RoundedRectangle(cornerRadius: tokens.r3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: tokens.r3, style: .continuous)
                .strokeBorder(focused ? tokens.accent : tokens.border, lineWidth: 1))
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
