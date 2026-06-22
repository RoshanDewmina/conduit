#if os(iOS)
import SwiftUI
import DesignSystem
import SSHTransport

public struct OnboardingPairScreen: View {
    @ObservedObject public var client: E2ERelayClient
    public let qrImage: Image?
    public let pairingCode: String
    public let onScanTapped: () -> Void
    @Environment(\.lancerTokens) private var t

    public init(
        client: E2ERelayClient,
        qrImage: Image?,
        pairingCode: String,
        onScanTapped: @escaping () -> Void
    ) {
        self.client = client
        self.qrImage = qrImage
        self.pairingCode = pairingCode
        self.onScanTapped = onScanTapped
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 32)

                Text("Pair the bridge")
                    .font(.dsMonoPt(24, weight: .bold))
                    .foregroundStyle(t.text)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                    .padding(.horizontal, 18)

                Text("Run this where your agents live. It dials out and prints a QR — no SSH, no port-forwarding.")
                    .font(.dsSansPt(14.5))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                DSQuoteBlock(
                    title: "INSTALL",
                    tags: [],
                    message: "curl -fsSL conduit.dev/install | sh",
                    tone: .ok
                )
                .padding(.horizontal, 18)
                .padding(.top, 22)

                VStack(alignment: .leading, spacing: 10) {
                    Text("OR ENTER PAIRING CODE")
                        .font(.dsMonoPt(10))
                        .tracking(10 * 0.12)
                        .foregroundStyle(t.text3)

                    Text(pairingCode)
                        .font(.dsMonoPt(26, weight: .bold))
                        .foregroundStyle(t.text)
                        .kerning(4)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 16)
                        .background(t.surfaceSunk)
                        .overlay(
                            Rectangle()
                                .strokeBorder(t.border, lineWidth: 1)
                        )

                    Text("auto-pairs once the install finishes")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        }
    }
}
#endif
