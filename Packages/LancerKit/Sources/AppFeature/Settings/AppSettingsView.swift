#if os(iOS)
import SwiftUI
import AccountKit
import LancerCore

/// Workspaces shell settings hierarchy — Profile pushes this onto one NavigationStack,
/// or Workspaces presents it as a sheet root.
public struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RelayFleetStore.self) private var relayFleetStore
    @Environment(TerminalSessionCoordinator.self) private var terminalCoordinator

    /// When true, this view is pushed inside a parent `NavigationStack` (Profile)
    /// and must not wrap another stack or add a sheet Close button.
    private let embedsInParentNavigation: Bool

    @State private var confirmingEmergencyStop = false
    @State private var isStopping = false
    @State private var emergencyStopError: String?
    @State private var lastStoppedRuns: Int?
    @State private var isFeedbackPresented = false

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
        .confirmationDialog(
            AppSettingsCopy.emergencyStopConfirmTitle,
            isPresented: $confirmingEmergencyStop,
            titleVisibility: .visible
        ) {
            Button(AppSettingsCopy.emergencyStopConfirmAction, role: .destructive) {
                Task { await performEmergencyStop() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(AppSettingsCopy.emergencyStopConfirmMessage)
        }
        .sheet(isPresented: $isFeedbackPresented) {
            FeedbackView()
        }
    }

    private var settingsList: some View {
        List {
            connectionsSection
            policyGovernanceSection
            supportSection
            emergencyStopSection
        }
        .accessibilityIdentifier("cursor.settings")
    }

    private var connectionsSection: some View {
        Section(AppSettingsCopy.connectionsSectionTitle) {
            NavigationLink {
                TrustedMachinesView(embedsInParentNavigation: true)
                    .environment(relayFleetStore)
                    .environment(terminalCoordinator)
            } label: {
                Label {
                    Text("Trusted machines")
                } icon: {
                    Image(systemName: "desktopcomputer")
                }
            }
            .accessibilityIdentifier("cursor.settings.row.trusted-machines")

            NavigationLink {
                AccountsUsageView()
                    .environment(relayFleetStore)
            } label: {
                Label {
                    Text("Accounts & Usage")
                } icon: {
                    Image(systemName: "person.crop.circle")
                }
            }
            .accessibilityIdentifier("cursor.settings.row.accounts-usage")
        }
    }

    private var policyGovernanceSection: some View {
        Section(AppSettingsCopy.policyGovernanceTitle) {
            NavigationLink {
                PolicyEditorView()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppSettingsCopy.policyRowTitle)
                    Text(AppSettingsCopy.policyRowDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("cursor.settings.row.policy")

            NavigationLink {
                AuditFeedView()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppSettingsCopy.auditRowTitle)
                    Text(AppSettingsCopy.auditRowDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("cursor.settings.row.audit")
        }
    }

    private var supportSection: some View {
        Section {
            Button {
                isFeedbackPresented = true
            } label: {
                Label {
                    Text("Send Feedback")
                } icon: {
                    Image(systemName: "envelope")
                }
            }
            .accessibilityIdentifier("cursor.settings.row.send-feedback")
        }
    }

    private var emergencyStopSection: some View {
        Section {
            Button(role: .destructive) {
                emergencyStopError = nil
                confirmingEmergencyStop = true
            } label: {
                HStack {
                    if isStopping {
                        ProgressView()
                    }
                    Text(AppSettingsCopy.emergencyStopButtonTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .disabled(isStopping)
            .accessibilityIdentifier("cursor.settings.emergency-stop")

            if let lastStoppedRuns {
                Text("Stopped \(lastStoppedRuns) run\(lastStoppedRuns == 1 ? "" : "s"). New launches are blocked on the host until re-enabled.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("cursor.settings.emergency-stop.result")
            }
            if let emergencyStopError {
                Text(emergencyStopError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("cursor.settings.emergency-stop.error")
            }
        } header: {
            Text(AppSettingsCopy.emergencyStopSectionTitle)
                .foregroundStyle(.red)
        } footer: {
            Text("Stops all runs and blocks new launches until re-enabled. Requires a connected host (SSH or relay).")
        }
    }

    @MainActor
    private func performEmergencyStop() async {
        isStopping = true
        emergencyStopError = nil
        lastStoppedRuns = nil
        defer { isStopping = false }
        do {
            let result = try await GovernanceHostActions.emergencyStop(relayFleetStore: relayFleetStore)
            // Fail-closed: only surface success fields from a decoded RPC result.
            guard result.emergencyStopped else {
                emergencyStopError = "Host did not confirm emergency stop."
                return
            }
            lastStoppedRuns = result.stoppedRuns
        } catch {
            emergencyStopError = error.localizedDescription
        }
    }
}
#endif
