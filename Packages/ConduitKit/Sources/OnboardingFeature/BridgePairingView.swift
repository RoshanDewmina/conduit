#if os(iOS)
import SwiftUI
import DesignSystem
import SecurityKit
import ConduitCore

public struct BridgePairingView: View {
    @State private var pairingCode = PairingCrypto.generatePairingCode()
    @State private var pairingState: PairingState = .waiting
    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss

    public var onUseSSH: () -> Void
    public var onPaired: ((String, String) -> Void)?

    public init(onUseSSH: @escaping () -> Void, onPaired: ((String, String) -> Void)? = nil) {
        self.onUseSSH = onUseSSH
        self.onPaired = onPaired
    }

    private enum PairingState {
        case waiting
        case paired
        case error(String)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("pair bridge", onBack: { dismiss() })

                    VStack(alignment: .leading, spacing: 22) {
                        Text("Install the bridge on the machine where your agents run — it dials out and pairs to this phone. No SSH, no port-forwarding, works on any network.")
                            .font(.dsSansPt(14.5))
                            .foregroundStyle(t.text2)
                            .fixedSize(horizontal: false, vertical: true)

                        DSQuoteBlock(
                            title: "INSTALL",
                            tags: [],
                            message: "curl -fsSL conduit.dev/install | sh",
                            tone: .ok
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            Text("PAIRING CODE")
                                .font(.dsMonoPt(10, weight: .medium))
                                .tracking(10 * 0.12)
                                .foregroundStyle(t.text3)

                            pairingCodeGrid

                            Text(pairingCode)
                                .font(.dsMonoPt(26, weight: .bold))
                                .foregroundStyle(t.text)
                                .kerning(4)

                            Text("scan, or it auto-pairs on install")
                                .font(.dsMonoPt(11))
                                .foregroundStyle(t.text3)
                        }

                        pairingStatusCard

                        Button(action: onUseSSH) {
                            HStack {
                                Text("advanced · connect a remote host over SSH")
                                    .font(.dsMonoPt(12.5))
                                    .foregroundStyle(t.text2)
                                Spacer()
                                DSIconView(.chevronRight, size: 15, color: t.text3)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 36)
                }
            }
        }
        .task { startPairingListener() }
    }

    private var pairingCodeGrid: some View {
        let gridSize = 7
        let cells = Array(0..<(gridSize * gridSize))
        return VStack(spacing: 2) {
            ForEach(0..<gridSize, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<gridSize, id: \.self) { col in
                        let idx = row * gridSize + col
                        let seed = pairingCode + String(idx)
                        let filled = seed.stableHash % 10 < 4
                        RoundedRectangle(cornerRadius: 1)
                            .fill(filled ? t.text2 : Color.clear)
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
        .padding(12)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: t.r3, style: .continuous)
            .strokeBorder(t.border, lineWidth: 1))
        .frame(maxWidth: 120)
    }

    @ViewBuilder
    private var pairingStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(pairingStateColor)
                    .frame(width: 8, height: 8)
                Text(pairingStateLabel)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: t.r4, style: .continuous)
            .strokeBorder(t.border, lineWidth: 1))
    }

    private var pairingStateColor: Color {
        switch pairingState {
        case .waiting: return t.accent
        case .paired: return t.risk(0)
        case .error: return t.danger
        }
    }

    private var pairingStateLabel: String {
        switch pairingState {
        case .waiting: return "waiting for bridge…"
        case .paired: return "paired"
        case .error(let msg): return msg
        }
    }

    private func startPairingListener() {
        Task {
            let keypair = PairingCrypto.generateKeyPair()
            let publicKey = keypair.publicKeyBase64URL
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run { pairingState = .paired }
            if let onPaired { onPaired(publicKey, pairingCode) }
        }
    }
}

extension String {
    fileprivate var stableHash: Int {
        var h = 0
        for b in utf8 { h = h &* 31 &+ Int(b) }
        return abs(h)
    }
}

public extension PairingCrypto {
    static func generatePairingCode() -> String {
        let digits = (0..<6).map { _ in Int.random(in: 0...9) }
        return digits.map(String.init).joined()
    }
}
#endif
