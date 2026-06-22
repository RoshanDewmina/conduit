#if os(iOS)
import SwiftUI
import LancerCore
import DesignSystem

public struct SnippetPaletteSheet: View {
    public let snippets: [Snippet]
    public let onInsert: (Snippet, String) -> Void
    public let onDismiss: () -> Void
    public let executeShellCommand: ((String) async -> String)?

    @State private var searchText: String = ""
    @State private var fillingSnippet: Snippet? = nil
    @Environment(\.lancerTokens) private var t

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
            ZStack {
                t.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    DSSearchField(text: $searchText, placeholder: "Search snippets")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(t.surface)
                        .overlay(t.border.frame(height: 0.5), alignment: .bottom)

                    if filtered.isEmpty {
                        DSEmptyState(
                            icon: .list,
                            title: snippets.isEmpty ? "No snippets" : "No results",
                            subtitle: snippets.isEmpty
                                ? "Add snippets in Settings to reuse commands."
                                : "Try a different search term."
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filtered) { snippet in
                                    snippetRow(snippet)
                                    t.divider.frame(height: 0.5)
                                }
                            }
                            .background(t.surface)
                            .clipShape(RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous)
                                    .strokeBorder(t.border, lineWidth: 0.5)
                            )
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
            .navigationTitle("Snippets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                        .foregroundStyle(t.accent)
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

    private func snippetRow(_ snippet: Snippet) -> some View {
        Button {
            if snippet.arguments.isEmpty {
                onInsert(snippet, snippet.body)
            } else {
                fillingSnippet = snippet
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(snippet.name)
                        .font(.dsSansPt(14, weight: .semibold))
                        .foregroundStyle(t.text)
                    Text(snippet.body)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                        .lineLimit(2)
                    if !snippet.arguments.isEmpty {
                        HStack(spacing: 4) {
                            DSIconView(.command, size: 10, color: t.accent)
                            Text("\(snippet.arguments.count) param\(snippet.arguments.count == 1 ? "" : "s")")
                                .font(.dsSansPt(11))
                                .foregroundStyle(t.accent)
                        }
                    }
                }
                Spacer()
                DSIconView(.arrowReturn, size: 14, color: t.text4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    @Environment(\.lancerTokens) private var t

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
            ZStack {
                t.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Command preview
                        sectionHead("Command")
                        editorCard {
                            Text(snippet.body)
                                .font(.dsMonoPt(13))
                                .foregroundStyle(t.text2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                        .padding(.bottom, 16)

                        // Arguments
                        ForEach(snippet.arguments, id: \.name) { arg in
                            sectionHead(arg.name)
                            editorCard {
                                argumentField(for: arg)
                            }
                            if let desc = arg.description {
                                Text(desc)
                                    .font(.dsSansPt(12))
                                    .foregroundStyle(t.text3)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 4)
                            }
                            Spacer().frame(height: 16)
                        }

                        // Filled preview
                        sectionHead("Preview")
                        editorCard {
                            Text(filledBody)
                                .font(.dsMonoPt(13))
                                .foregroundStyle(t.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                        .padding(.bottom, 24)

                        HStack {
                            Spacer()
                            DSButton("Insert", variant: .primary, action: { onInsert(filledBody) })
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle(snippet.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(t.accent)
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
            .font(.dsMonoPt(14))
            .foregroundStyle(t.text)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

        case .enumValues(let options):
            VStack(spacing: 0) {
                ForEach(options, id: \.self) { option in
                    let selected = (values[arg.name] ?? options.first ?? "") == option
                    HStack {
                        Text(option)
                            .font(.dsSansPt(14))
                            .foregroundStyle(t.text)
                        Spacer()
                        if selected { DSIconView(.check, size: 14, color: t.accent) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                    .onTapGesture { values[arg.name] = option }
                    if option != options.last {
                        t.border.frame(height: 0.5).padding(.horizontal, 16)
                    }
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
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Loading options…").font(.dsSansPt(14)).foregroundStyle(t.text3)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            } else if opts.isEmpty {
                TextField(arg.defaultValue ?? "value", text: Binding(
                    get: { values[arg.name] ?? arg.defaultValue ?? "" },
                    set: { values[arg.name] = $0 }
                ))
                .font(.dsMonoPt(14))
                .foregroundStyle(t.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(opts, id: \.self) { option in
                        let selected = (values[arg.name] ?? opts.first ?? "") == option
                        HStack {
                            Text(option)
                                .font(.dsMonoPt(14))
                                .foregroundStyle(t.text)
                            Spacer()
                            if selected { DSIconView(.check, size: 14, color: t.accent) }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                        .onTapGesture { values[arg.name] = option }
                        if option != opts.last {
                            t.border.frame(height: 0.5).padding(.horizontal, 16)
                        }
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

    private func sectionHead(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.dsSansPt(11, weight: .semibold))
            .foregroundStyle(t.text3)
            .tracking(0.5)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
    }

    private func editorCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(t.surface, in: RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
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
