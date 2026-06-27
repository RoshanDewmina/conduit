#if os(iOS)
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import DesignSystem
import SecurityKit
import SSHTransport
import LancerCore

/// Keyless QR + blind-relay pairing screen.
///
/// The phone is the source of trust: it generates an ephemeral X25519 keypair
/// and a single-use 6-digit pairing code, encodes `{ v, relay, code, pk }` into
/// a real QR, and dials the blind relay. The host runs the installer + scans the
/// QR (or types the code); when the relay reports `peer_joined`, both ends derive
/// the same AES/ChaCha session key via `PairingCrypto` and the screen flips to
/// "paired". No private key ever leaves the phone.
///
/// The decorative grid + fake 1-second success are gone — the status reflects the
/// real `E2ERelayClient.connectionState` / `pairingState`.
public struct BridgePairingView: View {
    @StateObject private var client: E2ERelayClient
    /// True only when this view minted its own client (previews / standalone).
    /// When the app-wide client is injected, the view must NOT disconnect it on
    /// disappear — doing so tears down the live bridge the dispatch path depends
    /// on, dropping `E2ERelayBridge.isActive` right after a successful pair.
    private let ownsClient: Bool
    @State private var pairingCode: String
    @State private var qrImage: Image?
    @State private var showScanner = false
    @State private var showManualEntry = false
    @State private var manualCode = ""
    @State private var scanError: String?
    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss

    public var onUseSSH: () -> Void
    public var onPaired: ((String, String) -> Void)?

    /// - Parameter client: the app-wide `E2ERelayClient` so a successful pair
    ///   drives the live `ApprovalRelay.e2eBridge`. When nil, a self-owned client
    ///   is used (previews / standalone) and no live bridge is wired.
    public init(
        client: E2ERelayClient? = nil,
        onUseSSH: @escaping () -> Void,
        onPaired: ((String, String) -> Void)? = nil
    ) {
        let resolved = client ?? E2ERelayClient(
            relayURL: RelaySettings.url(),
            pairingCode: PairingCrypto.generatePairingCode()
        )
        self.ownsClient = (client == nil)
        _client = StateObject(wrappedValue: resolved)
        _pairingCode = State(initialValue: resolved.pairingCode)
        self.onUseSSH = onUseSSH
        self.onPaired = onPaired
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
                            message: "curl -fsSL lancersoftware.dev/install | sh && lancerd pair",
                            tone: .ok
                        )

                        qrSection
                        pairingStatusCard
                        scanFallbackRow

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
        .sheet(isPresented: $showScanner) { scannerSheet }
        .alert("Enter pairing code", isPresented: $showManualEntry) {
            TextField("6-digit code", text: $manualCode)
                .keyboardType(.numberPad)
            Button("Pair") { applyManualCode() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("If the host printed its own code, type it here to pair against it instead.")
        }
        .task { startPairing() }
        .onChange(of: client.pairingState) { _, state in
            if case .paired = state {
                onPaired?(client.publicKeyBase64URL, pairingCode)
            }
        }
        .onDisappear { if ownsClient { client.disconnect() } }
    }

    // MARK: - QR

    private var qrSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SCAN ON THE HOST")
                .font(.dsMonoPt(10, weight: .medium))
                .tracking(10 * 0.12)
                .foregroundStyle(t.text3)

            HStack {
                Spacer()
                Group {
                    if let qrImage {
                        qrImage
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
                .frame(width: 188, height: 188)
                .padding(14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1))
                Spacer()
            }

            HStack {
                Spacer()
                Text(pairingCode)
                    .font(.dsMonoPt(26, weight: .bold))
                    .foregroundStyle(t.text)
                    .kerning(4)
                Spacer()
            }

            HStack {
                Spacer()
                Text("`lancerd pair` scans this — or type the code on the host")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .multilineTextAlignment(.center)
                Spacer()
            }
        }
    }

    private var scanFallbackRow: some View {
        VStack(spacing: 10) {
            Button {
                scanError = nil
                showScanner = true
            } label: {
                HStack(spacing: 8) {
                    DSIconView(.chevronRight, size: 14, color: t.accent)
                    Text("scan a code shown by the host instead")
                        .font(.dsMonoPt(12.5))
                        .foregroundStyle(t.accent)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if let scanError {
                Text(scanError)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Scanner sheet

    private var scannerSheet: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            QRScannerView(
                onScan: { payload in
                    showScanner = false
                    applyScannedPayload(payload)
                },
                onUnavailable: { reason in
                    showScanner = false
                    scanError = reason + " Enter the code manually."
                    manualCode = ""
                    // Present the alert AFTER the scanner sheet finishes dismissing —
                    // SwiftUI swallows an alert raised during a sheet dismiss.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showManualEntry = true }
                }
            )
            .ignoresSafeArea()

            HStack {
                Button("Cancel") { showScanner = false }
                    .font(.dsSansPt(15, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                Button("Type code") {
                    showScanner = false
                    manualCode = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showManualEntry = true }
                }
                .font(.dsSansPt(15, weight: .medium))
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    // MARK: - Status

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
        switch client.pairingState {
        case .paired: return t.risk(0)
        case .pairingFailed: return t.danger
        case .waitingForPeer, .unpaired: return t.accent
        }
    }

    private var pairingStateLabel: String {
        switch client.pairingState {
        case .paired:
            return "paired"
        case .pairingFailed(let reason):
            return "pairing failed — \(reason)"
        case .waitingForPeer:
            return "waiting for bridge…"
        case .unpaired:
            switch client.connectionState {
            case .connecting:
                return "connecting to relay…"
            case .reconnecting:
                return "relay unreachable — retrying…"
            case .connected:
                return "waiting for bridge…"
            case .disconnected:
                return "not connected"
            }
        }
    }

    // MARK: - Actions

    private func startPairing() {
        let code = client.beginPairingSession()
        pairingCode = code
        client.relayURL = RelaySettings.url()
        renderQR()
        client.connect()
    }

    private func renderQR() {
        let payload = QRPairingPayload(
            v: 1,
            relay: client.relayURL.absoluteString,
            code: pairingCode,
            pk: client.publicKeyBase64URL
        )
        guard let data = try? JSONEncoder().encode(payload),
              let img = Self.makeQR(from: data) else {
            qrImage = nil
            return
        }
        qrImage = Image(uiImage: img)
    }

    /// Accept a payload scanned from a host-presented QR. Supports either the
    /// JSON payload format or a bare 6-digit code.
    private func applyScannedPayload(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let payload = try? JSONDecoder().decode(QRPairingPayload.self, from: data) {
            if let url = URL(string: payload.relay) { client.relayURL = url }
            applyCode(payload.code)
            return
        }
        let digits = trimmed.filter(\.isNumber)
        guard digits.count == 6 else {
            scanError = "That QR didn't contain a valid pairing payload."
            return
        }
        applyCode(digits)
    }

    private func applyManualCode() {
        let digits = manualCode.filter(\.isNumber)
        guard digits.count == 6 else {
            scanError = "Pairing codes are 6 digits."
            return
        }
        applyCode(digits)
    }

    private func applyCode(_ code: String) {
        scanError = nil
        client.disconnect()
        pairingCode = code
        client.pairingCode = code
        renderQR()
        client.connect()
    }

    private static func makeQR(from data: Data) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Wire format for the pairing QR. Kept intentionally small and stable so the
/// Go `lancerd pair` scanner can decode the same JSON.
private struct QRPairingPayload: Codable {
    let v: Int
    let relay: String
    let code: String
    let pk: String
}
#endif
