import SwiftUI
import DesignSystem

struct FirstRunView: View {
    @Environment(HostModel.self) private var host
    @Environment(\.lancerTokens) private var tokens
    @State private var step = 0
    var onFinish: () -> Void = {}

    var body: some View {
        VStack(spacing: 24) {
            stepContent
            Text("Step \(step + 1) of 3")
                .font(.dsSansPt(13))
                .foregroundStyle(tokens.text3)
        }
        .frame(minWidth: 520, minHeight: 420)
        .padding(40)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            welcomeStep
        case 1:
            hostServiceStep
        default:
            pairingStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Text("Welcome to Lancer")
                .font(.dsDisplayPt(28))
                .foregroundStyle(tokens.text)
                .multilineTextAlignment(.center)

            Text("Lancer lets you steer and approve AI coding agents on this Mac from your iPhone. Three quick steps to get set up.")
                .font(.dsSansPt(14))
                .foregroundStyle(tokens.text2)
                .multilineTextAlignment(.center)

            DSButton("Get started", variant: .primary) {
                step = 1
            }
        }
    }

    private var hostServiceStep: some View {
        VStack(spacing: 16) {
            Text("Start the Host Service")
                .font(.dsDisplayPt(20))
                .foregroundStyle(tokens.text)

            Text("Lancer needs a small background service, the Host Service, running on this Mac so your iPhone can reach your coding agents.")
                .font(.dsSansPt(14))
                .foregroundStyle(tokens.text2)
                .multilineTextAlignment(.center)

            hostServiceStatusRow

            Text("lancerd install")
                .font(.dsMonoPt(13))
                .foregroundStyle(tokens.text)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(tokens.surfaceSunk)
                .clipShape(RoundedRectangle(cornerRadius: tokens.r3, style: .continuous))

            HStack(spacing: 12) {
                DSButton("Check again", variant: .quiet) {
                    Task { await host.refresh() }
                }
                DSButton("Continue", variant: .primary) {
                    step = 2
                }
                .disabled(!isConnected)
            }

            Button("Back") {
                step = 0
            }
        }
    }

    private var pairingStep: some View {
        VStack(spacing: 16) {
            Text("Pair your phone")
                .font(.dsDisplayPt(20))
                .foregroundStyle(tokens.text)

            Text("Open Lancer on your iPhone and scan the pairing code from the Devices tab. You can always pair more devices later from Devices.")
                .font(.dsSansPt(14))
                .foregroundStyle(tokens.text2)
                .multilineTextAlignment(.center)

            DSButton("Finish", variant: .primary) {
                onFinish()
            }

            Button("Back") {
                step = 1
            }
        }
    }

    private var hostServiceStatusRow: some View {
        HStack(spacing: 8) {
            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(tokens.ok)
                Text("Host Service is running")
                    .font(.dsSansPt(13, weight: .medium))
                    .foregroundStyle(tokens.ok)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(tokens.warn)
                Text("Host Service not detected")
                    .font(.dsSansPt(13, weight: .medium))
                    .foregroundStyle(tokens.warn)
            }
        }
    }

    private var isConnected: Bool {
        if case .connected = host.connection { return true } else { return false }
    }
}
