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

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Unknown Host Key")
                        .font(.headline)
                    Text("The authenticity of \(hostName) cannot be established.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Fingerprint (SHA256)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(fingerprint)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }

                Text("If you trust this host, tap **Trust & Connect**. If you are not expecting this fingerprint, tap **Cancel** and verify out-of-band.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

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
