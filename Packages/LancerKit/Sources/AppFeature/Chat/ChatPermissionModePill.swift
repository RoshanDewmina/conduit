#if os(iOS)
import SwiftUI
import LancerCore

/// Small tappable capsule that shows / sets the global `AutonomyPreset`
/// (permission mode). Distinct from the "Full tools" MCP toggle.
struct ChatPermissionModePill: View {
    @AppStorage(AutonomySelection.storageKey) private var presetRaw: String =
        AutonomySelection.default.rawValue

    private var preset: AutonomyPreset {
        AutonomySelection.resolve(presetRaw)
    }

    var body: some View {
        Menu {
            ForEach(AutonomyPreset.allCases, id: \.self) { option in
                Button {
                    presetRaw = option.rawValue
                } label: {
                    if option == preset {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 11, weight: .semibold))
                Text(preset.shortLabel)
                    .font(.system(size: 15, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color(.secondarySystemFill).opacity(0.6)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("permission-mode-pill")
        .accessibilityLabel(Text("Permission mode, \(preset.shortLabel)"))
        .accessibilityHint(Text("Choose how much the agent may do without asking"))
    }
}
#endif
