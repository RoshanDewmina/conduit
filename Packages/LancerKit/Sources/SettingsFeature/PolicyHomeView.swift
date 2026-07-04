#if os(iOS)
import SwiftUI
import DesignSystem
import LancerCore

// Policy = presets (the friendly front) + the cross-provider matrix (how a rule
// set realizes per agent). One screen, two segments — folded into Settings'
// "Policy & Governance" section (the former standalone Governance root).

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
            .accessibilityLabel("Policy section")

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
#endif
