#if os(iOS)
import SwiftUI
import DesignSystem
import LancerCore
import SettingsFeature

// Merged Governance surfaces: collapse the seven feature screens into three the
// user actually thinks in terms of — Policy (rules), Trust & Team (who/how we
// trust), and Audit (the record, which is a single view and needs no wrapper).
// Each wrapper owns the nav title; the embedded sub-views drop their own header.

/// Policy = presets (the friendly front) + the cross-provider matrix (how a rule
/// set realizes per agent). One screen, two segments.
public struct PolicyHomeView: View {
    let hosts: [String]
    let onApplyPreset: (PolicyPreset, String) -> Void
    let onApplyNormalized: (NormalizedPolicy) -> Void

    @Environment(\.lancerTokens) private var t
    @State private var tab = 0

    public init(
        hosts: [String],
        onApplyPreset: @escaping (PolicyPreset, String) -> Void,
        onApplyNormalized: @escaping (NormalizedPolicy) -> Void
    ) {
        self.hosts = hosts
        self.onApplyPreset = onApplyPreset
        self.onApplyNormalized = onApplyNormalized
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Presets").tag(0)
                Text("Providers").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if tab == 0 {
                PolicyPresetsView(hosts: hosts, embedded: true, onApply: onApplyPreset)
            } else {
                PolicyMatrixView(policy: .defaultPolicy, embedded: true, onApply: onApplyNormalized)
            }
        }
        .background(t.surface)
        .navigationTitle("Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Trust & Team = the privacy/E2E proof + who can approve/edit/stop. Two facets
/// of "who and how do we trust this," on one screen.
public struct TrustTeamView: View {
    let relayEncrypted: Bool
    let relayHost: String?
    let onOpenDevices: () -> Void
    let onOpenRelay: () -> Void

    @Environment(\.lancerTokens) private var t
    @State private var tab = 0

    public init(
        relayEncrypted: Bool,
        relayHost: String?,
        onOpenDevices: @escaping () -> Void,
        onOpenRelay: @escaping () -> Void
    ) {
        self.relayEncrypted = relayEncrypted
        self.relayHost = relayHost
        self.onOpenDevices = onOpenDevices
        self.onOpenRelay = onOpenRelay
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Privacy").tag(0)
                Text("Team").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if tab == 0 {
                TrustView(
                    relayEncrypted: relayEncrypted,
                    relayHost: relayHost,
                    embedded: true,
                    onOpenDevices: onOpenDevices,
                    onOpenRelay: onOpenRelay
                )
            } else {
                TeamRolesView(embedded: true)
            }
        }
        .background(t.surface)
        .navigationTitle("Trust & team")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
