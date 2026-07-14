#if os(iOS)
import SwiftUI
import LancerCore

/// Workspaces shell settings hierarchy — Profile pushes this onto one NavigationStack,
/// or Workspaces presents it as a sheet root.
public struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RelayFleetStore.self) private var relayFleetStore

    /// When true, this view is pushed inside a parent `NavigationStack` (Profile)
    /// and must not wrap another stack or add a sheet Close button.
    private let embedsInParentNavigation: Bool

    public init(embedsInParentNavigation: Bool = false) {
        self.embedsInParentNavigation = embedsInParentNavigation
    }

    public var body: some View {
        Group {
            if embedsInParentNavigation {
                settingsList
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                NavigationStack {
                    settingsList
                        .navigationTitle("Settings")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { dismiss() }
                            }
                        }
                }
            }
        }
    }

    private var settingsList: some View {
        List {
            connectionsSection
            policyGovernanceSection
        }
        .accessibilityIdentifier("cursor.settings")
    }

    private var connectionsSection: some View {
        Section(AppSettingsCopy.connectionsSectionTitle) {
            NavigationLink {
                TrustedMachinesView(embedsInParentNavigation: true)
                    .environment(relayFleetStore)
            } label: {
                Label {
                    Text("Trusted machines")
                } icon: {
                    Image(systemName: "desktopcomputer")
                }
            }
            .accessibilityIdentifier("cursor.settings.row.trusted-machines")
        }
    }

    private var policyGovernanceSection: some View {
        Section(AppSettingsCopy.policyGovernanceTitle) {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppSettingsCopy.policyGovernanceTitle)
                    .font(.body)
                Text(AppSettingsCopy.policyGovernanceDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("cursor.settings.policy-deferred")
            .accessibilityElement(children: .combine)
        }
    }
}
#endif
