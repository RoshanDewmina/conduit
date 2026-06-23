#if os(iOS)
import SwiftUI
import DesignSystem
import LancerCore
import SecurityKit
import SSHTransport

// MARK: - OnboardingView (4-step flow: Welcome → Pair → Caution → First run)

/// Dark onboarding walkthrough matching the FLOW 01 design.
///
/// Four indicator steps — Welcome, Pair the bridge, How cautious?, You're set — where the Pair
/// step has two in-flow sub-screens (Scan QR, Bridge paired). All screens render through
/// `OnboardingScaffold` so the chrome (leading control top-left, page dots top-right) stays
/// consistent. Pairing is real: it drives the app-wide `E2ERelayClient` (QR + 6-digit code +
/// camera scan), auto-advancing to "Bridge paired" when `pairingState` flips.
public struct OnboardingView: View {

    /// In-flow phases. `pair`/`scan`/`paired` all sit under indicator step 1.
    public enum Phase: Equatable {
        case welcome, installBridge, pair, scan, paired, caution, firstRun
    }

    public let onContinue: () -> Void
    public let onAlreadyUseLancer: () -> Void
    public let onSetupWorkspace: () -> Void

    @StateObject private var client: E2ERelayClient
    @State private var phase: Phase
    @State private var pairingCode: String = ""
    @State private var qrImage: Image?
    @State private var cautionLevel: OnboardingCautionLevel = .balanced
    @State private var didStartPairing = false
    @State private var showManualEntry = false
    @State private var manualCode = ""
    @State private var scanError: String?

    @AppStorage("lancer.onboarding.autonomyPreset") private var storedPreset: String = ""

    @Environment(\.lancerTokens) private var t

    private static let totalSteps = 4

    public init(
        onContinue: @escaping () -> Void,
        onAlreadyUseLancer: @escaping () -> Void = {},
        onSetupWorkspace: @escaping () -> Void = {},
        relayClient: E2ERelayClient? = nil,
        startPhase: Phase = .welcome
    ) {
        self.onContinue = onContinue
        self.onAlreadyUseLancer = onAlreadyUseLancer
        self.onSetupWorkspace = onSetupWorkspace
        let resolved = relayClient ?? E2ERelayClient(
            relayURL: RelaySettings.url(),
            pairingCode: PairingCrypto.generatePairingCode()
        )
        _client = StateObject(wrappedValue: resolved)
        _phase = State(initialValue: startPhase)
    }

    public var body: some View {
        OnboardingScaffold(
            stepIndex: dotIndex,
            totalSteps: Self.totalSteps,
            leading: leadingControl,
            onLeading: handleLeading
        ) {
            screenBody
                .transition(.opacity)
                .id(phase)
        } footer: {
            OnboardingFooter { footerCTA }
                .id(phase)
        }
        .onChange(of: phase) { _, new in
            if new == .pair { startPairingIfNeeded() }
        }
        .onChange(of: client.pairingState) { _, state in
            if state == .paired, phase == .pair || phase == .scan {
                withAnimation { phase = .paired }
            }
        }
        .onAppear { if phase == .pair { startPairingIfNeeded() } }
        .alert("Enter pairing code", isPresented: $showManualEntry) {
            TextField("6-digit code", text: $manualCode)
                .keyboardType(.numberPad)
            Button("Pair") { applyManualCode() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(scanError ?? "Type the 6-digit code shown by your host.")
        }
    }

    // MARK: Screen switcher

    @ViewBuilder
    private var screenBody: some View {
        switch phase {
        case .welcome:
            OnboardingWelcomeScreen()
        case .installBridge:
            OnboardingInstallBridgeScreen()
        case .pair:
            OnboardingPairScreen(
                client: client,
                qrImage: qrImage,
                pairingCode: pairingCode,
                onScanTapped: { withAnimation { phase = .scan } }
            )
        case .scan:
            OnboardingScanScreen(
                onScan: { payload in applyScanned(payload) },
                onUnavailable: { reason in
                    scanError = reason + " Enter the code manually."
                    manualCode = ""
                    withAnimation { phase = .pair }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showManualEntry = true
                    }
                },
                onEnterCodeInstead: {
                    scanError = nil
                    manualCode = ""
                    showManualEntry = true
                }
            )
        case .paired:
            OnboardingPairedScreen(hostName: "Dev VPS", agents: "claude-code · codex")
        case .caution:
            OnboardingCautionScreen(level: $cautionLevel)
        case .firstRun:
            OnboardingFirstRunScreen(
                cautionTitle: cautionLevel.title.lowercased(),
                onRunDemo: finish
            )
        }
    }

    // MARK: Footer CTA per phase

    @ViewBuilder
    private var footerCTA: some View {
        switch phase {
        case .welcome:
            DSButton("get started", variant: .primary, size: .lg, fullWidth: true) {
                withAnimation { phase = .installBridge }
            }
        case .installBridge:
            DSButton("I've installed it", variant: .primary, size: .lg, fullWidth: true) {
                withAnimation { phase = .pair }
            }
        case .pair:
            DSButton("scan qr code", variant: .primary, size: .lg, fullWidth: true) {
                withAnimation { phase = .scan }
            }
        case .scan:
            Button {
                scanError = nil
                manualCode = ""
                showManualEntry = true
            } label: {
                Text("enter 6-digit code instead")
                    .font(.dsMonoPt(13))
                    .foregroundStyle(t.text3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        case .paired:
            DSButton("continue", variant: .primary, size: .lg, fullWidth: true) {
                withAnimation { phase = .caution }
            }
        case .caution:
            DSButton("connect & finish", variant: .primary, size: .lg, fullWidth: true) {
                persistPreset()
                withAnimation { phase = .firstRun }
            }
        case .firstRun:
            DSButton("continue", variant: .primary, size: .lg, fullWidth: true) {
                finish()
            }
        }
    }

    // MARK: Chrome helpers

    private var dotIndex: Int {
        switch phase {
        case .welcome, .installBridge: return 0
        case .pair, .scan, .paired:    return 1
        case .caution:                 return 2
        case .firstRun:                return 3
        }
    }

    private var leadingControl: OnboardingLeadingControl {
        switch phase {
        case .welcome:                              return .none
        case .scan:                                 return .close
        case .installBridge, .pair, .paired, .caution, .firstRun: return .back
        }
    }

    private func handleLeading() {
        switch phase {
        case .installBridge:
            withAnimation { phase = .welcome }
        case .pair:
            client.disconnect()
            didStartPairing = false
            withAnimation { phase = .installBridge }
        case .scan:
            withAnimation { phase = .pair }
        case .paired:
            withAnimation { phase = .pair }
        case .caution:
            withAnimation { phase = .paired }
        case .firstRun:
            withAnimation { phase = .caution }
        case .welcome:
            break
        }
    }

    // MARK: Pairing

    private func startPairingIfNeeded() {
        guard !didStartPairing else { return }
        didStartPairing = true
        let code = client.beginPairingSession()
        pairingCode = code
        client.relayURL = RelaySettings.url()
        qrImage = OnboardingPairing.renderQR(
            relay: client.relayURL,
            code: code,
            publicKey: client.publicKeyBase64URL
        )
        client.connect()
    }

    private func applyScanned(_ payload: String) {
        guard let code = OnboardingPairing.extractCode(fromScanned: payload) else {
            scanError = "That QR code wasn't a valid pairing code."
            manualCode = ""
            withAnimation { phase = .pair }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showManualEntry = true }
            return
        }
        applyCode(code)
        withAnimation { phase = .pair }
    }

    private func applyManualCode() {
        guard let code = OnboardingPairing.normalize(manualCode) else {
            scanError = "Pairing codes are 6 digits."
            showManualEntry = true
            return
        }
        applyCode(code)
    }

    private func applyCode(_ code: String) {
        scanError = nil
        client.disconnect()
        pairingCode = code
        client.pairingCode = code
        qrImage = OnboardingPairing.renderQR(
            relay: client.relayURL,
            code: code,
            publicKey: client.publicKeyBase64URL
        )
        client.connect()
    }

    // MARK: Finish

    private func persistPreset() {
        storedPreset = cautionLevel.mappedPreset.rawValue
        // Queue the chosen tier's starter policy; it's pushed to the daemon on the
        // first successful connect (the bridge isn't reachable yet during pairing).
        OnboardingPolicy.markPending(cautionLevel)
    }

    private func finish() {
        persistPreset()
        onContinue()
    }
}

// MARK: - Install Bridge Screen

private struct OnboardingInstallBridgeScreen: View {
    @Environment(\.lancerTokens) private var t

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 32)

                Text("Install Lancer on your computer")
                    .font(.dsMonoPt(24, weight: .bold))
                    .foregroundStyle(t.text)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                    .padding(.horizontal, 18)

                Text("Before you can pair, run the Lancer bridge daemon on the machine you want to control. It connects out through our relay — no port-forwarding needed.")
                    .font(.dsSansPt(14.5))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                DSQuoteBlock(
                    title: "INSTALL",
                    tags: [],
                    message: "curl -fsSL lancersoftware.dev/install | sh",
                    tone: .ok
                )
                .padding(.horizontal, 18)
                .padding(.top, 22)

                Text("Once it prints \"waiting to pair\", tap continue.")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text3)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        }
    }
}
#endif
