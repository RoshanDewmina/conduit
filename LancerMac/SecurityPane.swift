import SwiftUI
import DesignSystem
import LancerCore
import HostControlKit

struct SecurityPane: View {
    @Environment(HostModel.self) private var host
    @Environment(\.lancerTokens) private var tokens
    @State private var phrase: String?
    @State private var revealing = false
    @State private var phraseError: String?
    @State private var showRemoveHelp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Security")
                    .font(.dsDisplayPt(22))
                    .foregroundStyle(tokens.text)

                GroupBox("Security checks") {
                    securityChecksContent
                        .padding(.top, 4)
                }

                GroupBox("Verification phrase") {
                    verificationPhraseContent
                        .padding(.top, 4)
                }

                GroupBox("Local keys & credentials") {
                    VStack(alignment: .leading, spacing: 10) {
                        labeledRow("Keychain", value: "Stored behind the device's secure enclave")
                        labeledRow("IPC token", value: "~/.lancer/ipc-token (local only)")
                    }
                    .padding(.top, 4)
                }

                GroupBox("Remove Lancer") {
                    removeLancerContent
                        .padding(.top, 4)
                }

                Spacer()
            }
            .padding(24)
        }
        .confirmationDialog("Remove Lancer?", isPresented: $showRemoveHelp, titleVisibility: .visible) {
            Button("OK") {}
        } message: {
            Text("Run the command shown below in a terminal to remove the background service, PATH shims, and the installed binary. Your config, pairings, and Keychain keys are left intact.")
        }
    }

    @ViewBuilder
    private var securityChecksContent: some View {
        if let doctor = host.doctor {
            let relevant = doctor.checks.filter(isSecurityRelevant)
            if relevant.isEmpty {
                Text("No security-related checks reported.")
                    .font(.dsSansPt(13))
                    .foregroundStyle(tokens.text3)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(relevant) { check in
                        checkRow(check)
                        Divider()
                    }
                }
            }
        } else {
            Text("Run Diagnostics to load security checks.")
                .font(.dsSansPt(13))
                .foregroundStyle(tokens.text3)
        }
    }

    private func isSecurityRelevant(_ check: DoctorCheckResult) -> Bool {
        let keywords = ["key", "token", "relay", "host", "trust", "biometr"]
        return keywords.contains { check.name.localizedCaseInsensitiveContains($0) }
    }

    private func checkRow(_ check: DoctorCheckResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(check.passed ? tokens.ok : tokens.danger)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.name)
                    .font(.dsSansPt(13, weight: .medium))
                    .foregroundStyle(tokens.text)
                Text(check.message)
                    .font(.dsSansPt(12))
                    .foregroundStyle(tokens.text2)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var verificationPhraseContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("When you pair a phone, confirm this exact phrase appears on both screens — it proves no machine-in-the-middle swapped the key.")
                .font(.dsSansPt(12))
                .foregroundStyle(tokens.text2)

            DSButton("Reveal phrase", systemImage: "checkmark.shield", isLoading: revealing) {
                revealPhrase()
            }
            .disabled(revealing)

            if let phraseError {
                Text(phraseError)
                    .font(.dsSansPt(12))
                    .foregroundStyle(tokens.danger)
            } else if let phrase, !phrase.isEmpty {
                Text(phrase)
                    .font(.dsMonoPt(13))
                    .foregroundStyle(tokens.accent)
                    .textSelection(.enabled)
            }
        }
    }

    private func revealPhrase() {
        revealing = true
        phraseError = nil
        Task {
            defer { revealing = false }
            guard let payload = try? await host.beginPairing(), !payload.publicKey.isEmpty else {
                phraseError = "Host Service unreachable"
                phrase = nil
                return
            }
            phrase = VerificationPhrase.make(fromPublicKey: payload.publicKey)
        }
    }

    @ViewBuilder
    private var removeLancerContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Uninstalling removes the background service, PATH shims, and the installed binary. Your config, pairings, and Keychain keys are left intact.")
                .font(.dsSansPt(12))
                .foregroundStyle(tokens.text2)

            Text("lancerd uninstall")
                .font(.dsMonoPt(13))
                .foregroundStyle(tokens.text)
                .textSelection(.enabled)

            DSButton("Remove Lancer…", systemImage: "trash", variant: .destructive) {
                showRemoveHelp = true
            }
        }
    }

    private func labeledRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.dsSansPt(13))
                .foregroundStyle(tokens.text2)
            Spacer()
            Text(value)
                .font(.dsSansPt(13))
                .foregroundStyle(tokens.text)
                .multilineTextAlignment(.trailing)
        }
    }
}
