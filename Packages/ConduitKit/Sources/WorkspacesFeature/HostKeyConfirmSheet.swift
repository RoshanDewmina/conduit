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

    @Environment(\.conduitTokens) private var t

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                // Warning icon
                HStack(spacing: 12) {
                    Image(systemName: "shield.slash")
                        .font(.title2)
                        .foregroundStyle(t.warn)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unknown Host Key")
                            .font(.headline)
                            .foregroundStyle(t.text1)
                        Text("The authenticity of \(hostName) cannot be established.")
                            .font(.subheadline)
                            .foregroundStyle(t.text3)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Fingerprint (SHA256)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(t.text3)
                    Text(fingerprint)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(t.surf2)
                        .clipShape(RoundedRectangle(cornerRadius: t.radiusSM))
                        .foregroundStyle(t.text2)
                }

                Text("If you trust this host, tap **Trust & Connect**. If you are not expecting this fingerprint, tap **Cancel** and verify out-of-band.")
                    .font(.footnote)
                    .foregroundStyle(t.text3)

                Spacer()

                VStack(spacing: 12) {
                    Button(action: onTrust) {
                        Text("Trust & Connect")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .cancel, action: onReject) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(t.surf0)
            .navigationTitle("Verify Host")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onReject)
                }
            }
        }
    }
}
#endif
