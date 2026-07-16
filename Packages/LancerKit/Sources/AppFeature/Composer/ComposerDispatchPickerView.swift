#if os(iOS)
import SwiftUI
import LancerCore

/// Unified composer dispatch sheet — agent, model, full-tools, and permission
/// mode in one scrollable list with room for labels + subtitles (replaces the
/// four narrow inline chips that wrapped into letter-stacks).
public struct ComposerDispatchPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let selectedVendor: DispatchVendorSelection
    let selectedModel: DispatchModelSelection
    let fullToolsEnabled: Bool
    let selectedAutonomy: AutonomyPreset
    let installedVendors: [String]?
    let onSelectVendor: (DispatchVendorSelection) -> Void
    let onSelectModel: (DispatchModelSelection) -> Void
    let onToggleFullTools: (Bool) -> Void
    let onSelectAutonomy: (AutonomyPreset) -> Void

    public init(
        selectedVendor: DispatchVendorSelection,
        selectedModel: DispatchModelSelection,
        fullToolsEnabled: Bool,
        selectedAutonomy: AutonomyPreset,
        installedVendors: [String]?,
        onSelectVendor: @escaping (DispatchVendorSelection) -> Void,
        onSelectModel: @escaping (DispatchModelSelection) -> Void,
        onToggleFullTools: @escaping (Bool) -> Void,
        onSelectAutonomy: @escaping (AutonomyPreset) -> Void
    ) {
        self.selectedVendor = selectedVendor
        self.selectedModel = selectedModel
        self.fullToolsEnabled = fullToolsEnabled
        self.selectedAutonomy = selectedAutonomy
        self.installedVendors = installedVendors
        self.onSelectVendor = onSelectVendor
        self.onSelectModel = onSelectModel
        self.onToggleFullTools = onToggleFullTools
        self.onSelectAutonomy = onSelectAutonomy
    }

    private var vendorOptions: [DispatchVendorSelection] {
        DispatchVendorSelection.available(installed: installedVendors, keeping: selectedVendor)
    }

    private var showModelSection: Bool { selectedVendor.usesClaudeModelPicker }
    private var showFullToolsSection: Bool { selectedVendor.usesClaudeModelPicker }

    public var body: some View {
        VStack(spacing: 0) {
            RepoSheetHeader(title: "Dispatch") { dismiss() }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    agentSection
                    if showModelSection {
                        modelSection
                    }
                    if showFullToolsSection {
                        toolsSection
                    }
                    permissionSection
                }
                .padding(.bottom, 24)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
    }

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            RepoSectionHeader(title: "Agent")
                .padding(.top, 20)
            ForEach(vendorOptions, id: \.self) { vendor in
                pickerRow(
                    title: vendor.displayName,
                    subtitle: nil,
                    systemImage: vendor.systemImage,
                    isSelected: vendor == selectedVendor
                ) {
                    onSelectVendor(vendor)
                }
                Divider()
                    .padding(.leading, 58)
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            RepoSectionHeader(title: "Model")
                .padding(.top, 20)
            ForEach(DispatchModelSelection.allCases, id: \.self) { model in
                pickerRow(
                    title: model.displayName,
                    subtitle: modelSubtitle(model),
                    systemImage: "sparkles",
                    isSelected: model == selectedModel
                ) {
                    onSelectModel(model)
                }
                Divider()
                    .padding(.leading, 58)
            }
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            RepoSectionHeader(title: "Tools")
                .padding(.top, 20)
            Button {
                onToggleFullTools(!fullToolsEnabled)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Full tools")
                            .font(.system(size: 17))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text("Slower first reply; enables MCP tools")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    Toggle("", isOn: Binding(
                        get: { fullToolsEnabled },
                        set: { onToggleFullTools($0) }
                    ))
                    .labelsHidden()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("composer-full-tools-toggle")
            .accessibilityLabel(Text("Full tools"))
            .accessibilityValue(Text(fullToolsEnabled ? "On" : "Off"))
            Divider()
                .padding(.leading, 58)
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            RepoSectionHeader(title: "Permission mode")
                .padding(.top, 20)
            ForEach(AutonomyPreset.allCases, id: \.rawValue) { preset in
                pickerRow(
                    title: preset.label,
                    subtitle: preset.description,
                    systemImage: "shield.lefthalf.filled",
                    isSelected: preset == selectedAutonomy
                ) {
                    onSelectAutonomy(preset)
                }
                Divider()
                    .padding(.leading, 58)
            }
        }
    }

    private func modelSubtitle(_ model: DispatchModelSelection) -> String {
        switch model {
        case .haiku: return "Fastest replies"
        case .sonnet: return "Balanced speed and quality"
        case .opus: return "Highest quality"
        }
    }

    private func pickerRow(
        title: String,
        subtitle: String?,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    Color(.systemGroupedBackground)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            ComposerDispatchPickerView(
                selectedVendor: .claudeCode,
                selectedModel: .sonnet,
                fullToolsEnabled: true,
                selectedAutonomy: .autoSafeWrites,
                installedVendors: ["claudeCode", "codex"],
                onSelectVendor: { _ in },
                onSelectModel: { _ in },
                onToggleFullTools: { _ in },
                onSelectAutonomy: { _ in }
            )
        }
}
#endif
