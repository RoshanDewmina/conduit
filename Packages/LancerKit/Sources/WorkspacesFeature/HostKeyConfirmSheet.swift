#if os(iOS)
import SwiftUI
import DesignSystem

public struct HostKeyConfirmSheet: View {
    public let hostName: String
    public let fingerprint: String
    public let onTrust: () -> Void
    public let onReject: () -> Void

    public init(
        hostName: String,
        fingerprint: String,
        onTrust: @escaping () -> Void,
        onReject: @escaping () -> Void
    ) {
        self.hostName = hostName
        self.fingerprint = fingerprint
        self.onTrust = onTrust
        self.onReject = onReject
    }

    @Environment(\.lancerTokens) private var t

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                // Warning icon
                HStack(spacing: 12) {
                    DSIconView(.shield, size: 24, color: t.warn)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unknown Host Key")
                            .font(.dsSansPt(16, weight: .semibold))
                            .foregroundStyle(t.text)
                        Text("The authenticity of \(hostName) cannot be established.")
                            .font(.dsSansPt(13))
                            .foregroundStyle(t.text3)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Fingerprint (SHA256)")
                        .font(.dsSansPt(11, weight: .medium))
                        .foregroundStyle(t.text3)
                    Text(fingerprint)
                        .font(.dsMonoPt(12))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: t.radiusSM, style: .continuous))
                        .foregroundStyle(t.text2)
                        .foregroundStyle(t.text2)
                }

                Text("If you trust this host, tap **Trust & Connect**. If you are not expecting this fingerprint, tap **Cancel** and verify out-of-band.")
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)

                Spacer()

                VStack(spacing: 10) {
                    CursorPillButton(title: "Trust & Connect", style: .primary, action: onTrust)
                    CursorPillButton(title: "Cancel", style: .secondary, action: onReject)
                }
            }
            .padding()
            .background(t.bg)
            .navigationTitle("Verify Host")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onReject)
                        .foregroundStyle(t.accent)
                }
            }
        }
    }
}
#endif
