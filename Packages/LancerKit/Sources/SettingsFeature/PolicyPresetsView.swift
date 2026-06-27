#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import LancerCore
import DesignSystem

public struct PolicyPresetsView: View {
    private let hosts: [String]
    private let onApply: (PolicyPreset, String) -> Void
    /// When embedded in a merged Governance surface, the wrapper supplies the nav
    /// bar/title, so this view drops its own DSDetailHeader.
    private let embedded: Bool

    @State private var presets: [PolicyPreset] = []
    @State private var showingEditor = false
    @State private var editingPreset: PolicyPreset? = nil
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportData: Data? = nil
    @State private var errorMessage: String? = nil

    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss

    public init(hosts: [String] = [], embedded: Bool = false, onApply: @escaping (PolicyPreset, String) -> Void = { _, _ in }) {
        self.hosts = hosts
        self.embedded = embedded
        self.onApply = onApply
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !embedded {
                        DSDetailHeader("policy presets", onBack: { dismiss() })
                    }
                    presetsSection
                    addSection
                    importExportSection
                    if let msg = errorMessage {
                        Text(msg)
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.danger)
                            .padding(.horizontal, 18)
                            .padding(.top, 8)
                    }
                    Spacer(minLength: 32)
                }
            }
        }
        .navigationBarHidden(!embedded)
        .onAppear { reload() }
        .sheet(isPresented: $showingEditor, onDismiss: reload) {
            if let preset = editingPreset {
                NavigationStack {
                    PolicyEditorView(
                        cwd: "~",
                        initialYAML: preset.ruleYAML,
                        onReload: {},
                        onSave: { yaml in
                            let updated = PolicyPreset(
                                id: preset.id,
                                name: preset.name,
                                description: preset.description,
                                ruleYAML: yaml
                            )
                            PolicyPresetStore.shared.save(updated)
                        }
                    )
                }
            } else {
                NavigationStack {
                    NewPresetSheet(onSave: { preset in
                        PolicyPresetStore.shared.save(preset)
                    })
                }
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    let data = try Data(contentsOf: url)
                    try PolicyPresetStore.shared.importJSON(data)
                    reload()
                } catch {
                    errorMessage = error.localizedDescription
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: PolicyPresetsDocument(data: exportData ?? Data()),
            contentType: .json,
            defaultFilename: "lancer-policy-presets"
        ) { _ in
            exportData = nil
        }
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHead("PRESETS")
            if presets.isEmpty {
                card {
                    Text("No presets yet. Add one below.")
                        .font(.dsSansPt(13))
                        .foregroundStyle(t.text3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            } else {
                card {
                    ForEach(Array(presets.enumerated()), id: \.element.id) { idx, preset in
                        if idx > 0 { hairline }
                        presetRow(preset)
                    }
                }
            }
        }
    }

    private func presetRow(_ preset: PolicyPreset) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(preset.name)
                        .font(.dsMonoPt(13, weight: .medium))
                        .foregroundStyle(t.text)
                    if preset.id.hasPrefix("builtin.") {
                        DSChip("built-in", tone: .neutral, variant: .soft, size: .sm)
                    }
                }
                Text(preset.description)
                    .font(.dsSansPt(12))
                    .foregroundStyle(t.text3)
                    .lineLimit(2)
            }
            Spacer()
            HStack(spacing: 8) {
                if !preset.id.hasPrefix("builtin.") {
                    Button {
                        editingPreset = preset
                        showingEditor = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14))
                            .foregroundStyle(t.text3)
                    }
                    .buttonStyle(.plain)
                }
                if !hosts.isEmpty {
                    Menu {
                        ForEach(hosts, id: \.self) { host in
                            Button(host) { onApply(preset, host) }
                        }
                    } label: {
                        DSChip("Apply", tone: .accent, variant: .soft, size: .sm)
                    }
                }
                if !preset.id.hasPrefix("builtin.") {
                    Button {
                        PolicyPresetStore.shared.delete(id: preset.id)
                        reload()
                        Haptics.selection()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(t.danger)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHead("NEW PRESET")
            card {
                Button {
                    editingPreset = nil
                    showingEditor = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(t.accent)
                        Text("New preset")
                            .font(.dsSansPt(15, weight: .medium))
                            .foregroundStyle(t.text)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var importExportSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHead("TRANSFER")
            card {
                Button {
                    showingImporter = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 16))
                            .foregroundStyle(t.text2)
                            .frame(width: 22)
                        Text("Import JSON")
                            .font(.dsSansPt(15))
                            .foregroundStyle(t.text)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                hairline

                Button {
                    exportData = try? PolicyPresetStore.shared.exportJSON()
                    showingExporter = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                            .foregroundStyle(t.text2)
                            .frame(width: 22)
                        Text("Export JSON")
                            .font(.dsSansPt(15))
                            .foregroundStyle(t.text)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionHead(_ title: String) -> some View {
        Text(title)
            .font(.dsMonoPt(11, weight: .medium))
            .tracking(11 * 0.10)
            .foregroundStyle(t.text3)
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 6)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
            .padding(.horizontal, 18)
    }

    private var hairline: some View {
        DSDivider(.soft, leadingInset: 14)
    }

    private func reload() {
        presets = PolicyPresetStore.shared.all()
    }
}

// MARK: - NewPresetSheet

private struct NewPresetSheet: View {
    let onSave: (PolicyPreset) -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var ruleYAML = PolicyEditorView.strictPreset
    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("new preset", onBack: { dismiss() })
                    sectionHead("NAME")
                    fieldCard {
                        TextField("e.g. ci-relaxed", text: $name)
                            .font(.dsMonoPt(13))
                            .foregroundStyle(t.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }
                    sectionHead("DESCRIPTION")
                    fieldCard {
                        TextField("Short description", text: $description)
                            .font(.dsSansPt(13))
                            .foregroundStyle(t.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }
                    sectionHead("POLICY YAML")
                    TextEditor(text: $ruleYAML)
                        .font(.dsMonoPt(12.5))
                        .foregroundStyle(t.termText)
                        .scrollContentBackground(.hidden)
                        .background(t.termSurface)
                        .frame(minHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                                .strokeBorder(t.termBorder, lineWidth: 1)
                        )
                        .padding(.horizontal, 18)
                        .padding(.top, 6)
                    DSButton(
                        "Save preset",
                        variant: .accent,
                        size: .md,
                        mono: true,
                        fullWidth: true
                    ) {
                        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        let preset = PolicyPreset(
                            id: UUID().uuidString,
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                            ruleYAML: ruleYAML
                        )
                        onSave(preset)
                        dismiss()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func sectionHead(_ title: String) -> some View {
        Text(title)
            .font(.dsMonoPt(11, weight: .medium))
            .tracking(11 * 0.10)
            .foregroundStyle(t.text3)
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 6)
    }

    private func fieldCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
            .padding(.horizontal, 18)
    }
}

// MARK: - FileDocument shim for exporter

private struct PolicyPresetsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    NavigationStack {
        PolicyPresetsView(
            hosts: ["macbook.local", "dev-server"],
            onApply: { preset, host in
                print("Apply \(preset.name) → \(host)")
            }
        )
    }
}
#endif
