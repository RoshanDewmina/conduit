#if os(iOS)
import SwiftUI
import Observation
import ConduitCore
import DesignSystem
import SSHTransport

@MainActor @Observable
public final class SecretsViewModel {
    public var secrets: [SecretEntry] = []
    public var pendingRequests: [PendingSecretRequest] = []
    public var isLoading = false
    public var errorMessage: String?
    public var showAddSheet = false
    public var newSecretName = ""
    public var newSecretScope = ""
    public var newSecretValue = ""
    public var newSecretType: SecretRequest.CredentialType = .apiKey

    private var channel: DaemonChannel?

    public init() {}

    public func attach(channel: DaemonChannel) {
        self.channel = channel
    }

    public func load() async {
        guard let channel else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await channel.listSecrets()
            secrets = result.secrets ?? []
            pendingRequests = result.pending ?? []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func addSecret() async {
        guard let channel, !newSecretName.isEmpty, !newSecretValue.isEmpty else { return }
        do {
            _ = try await channel.storeSecret(
                name: newSecretName,
                type: newSecretType.rawValue,
                scope: newSecretScope,
                value: newSecretValue
            )
            newSecretName = ""
            newSecretScope = ""
            newSecretValue = ""
            showAddSheet = false
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func authorize(_ requestID: String, scope: String) async {
        guard let channel else { return }
        do {
            _ = try await channel.authorizeSecret(requestID: requestID, scope: scope)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func revoke(_ requestID: String) async {
        guard let channel else { return }
        do {
            _ = try await channel.revokeSecret(requestID: requestID)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func delete(_ secretID: String) async {
        guard let channel else { return }
        do {
            _ = try await channel.deleteSecret(secretID: secretID)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

public struct SecretsView: View {
    @State private var vm: SecretsViewModel
    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: SecretsViewModel) {
        _vm = State(initialValue: viewModel)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("secrets", onBack: { dismiss() })

                    Text("Stored credentials let agents act on your behalf with scoped, time-limited authorization. The secret value stays on the daemon and is never sent to an agent.")
                        .font(.dsSansPt(14))
                        .foregroundStyle(t.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .padding(.bottom, 16)

                    if !vm.pendingRequests.isEmpty {
                        sectionHead("PENDING REQUESTS")
                        card {
                            ForEach(Array(vm.pendingRequests.enumerated()), id: \.element.id) { index, pending in
                                if index > 0 { hairline }
                                PendingSecretRow(
                                    request: pending,
                                    onAuthorize: { scope in
                                        Task { await vm.authorize(pending.request.id, scope: scope) }
                                    },
                                    onDeny: {
                                        Task { await vm.revoke(pending.request.id) }
                                    }
                                )
                            }
                        }
                    }

                    sectionHead("STORED SECRETS")
                    if vm.secrets.isEmpty, !vm.isLoading {
                        emptyState
                    } else {
                        card {
                            ForEach(Array(vm.secrets.enumerated()), id: \.element.id) { index, secret in
                                if index > 0 { hairline }
                                SecretRow(secret: secret) {
                                    Task { await vm.delete(secret.id) }
                                }
                            }
                        }
                    }

                    addButton

                    if !vm.secrets.isEmpty {
                        Text("\(vm.secrets.count) secret\(vm.secrets.count == 1 ? "" : "s") stored")
                            .font(.dsSansPt(12))
                            .foregroundStyle(t.text3)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 14)
                            .padding(.bottom, 36)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $vm.showAddSheet) {
            AddSecretSheet(vm: vm)
        }
        .task { await vm.load() }
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var addButton: some View {
        Button { vm.showAddSheet = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.dsSansPt(13, weight: .semibold))
                Text("Add secret")
                    .font(.dsSansPt(14, weight: .medium))
            }
            .foregroundStyle(t.accentFg)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(t.accent)
            .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .accessibilityLabel("Add secret")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 28))
                .foregroundStyle(t.text4)
            Text("No secrets stored")
                .font(.dsSansPt(15, weight: .medium))
                .foregroundStyle(t.text2)
            Text("Add credentials to let agents use them with scoped authorization.")
                .font(.dsSansPt(13))
                .foregroundStyle(t.text3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }

    private func sectionHead(_ title: String) -> some View {
        Text(title)
            .font(.dsMonoPt(11, weight: .medium))
            .tracking(11 * 0.10)
            .foregroundStyle(t.text3)
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 6)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
            .padding(.horizontal, 18)
    }

    private var hairline: some View {
        DSDivider(.soft, leadingInset: 16)
    }
}

private struct SecretRow: View {
    let secret: SecretEntry
    let onDelete: () -> Void
    @Environment(\.conduitTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: iconForType(secret.type))
                    .font(.system(size: 14))
                    .foregroundStyle(t.accent)
                    .frame(width: 20, alignment: .center)
                Text(secret.name)
                    .font(.dsSansPt(15, weight: .medium))
                    .foregroundStyle(t.text)
                Spacer(minLength: 8)
                if secret.useCount > 0 {
                    Text("\(secret.useCount)×")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                }
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                        .font(.dsSansPt(13))
                        .foregroundStyle(t.danger)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete secret \(secret.name)")
            }
            if !secret.scope.isEmpty {
                Text("Scope: \(secret.scope)")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text2)
                    .padding(.leading, 30)
            }
            HStack(spacing: 8) {
                DSChip(secret.type.rawValue, tone: .neutral, variant: .soft, size: .sm)
                if let lastUsed = secret.lastUsedAt {
                    Text("Last used \(lastUsed.formatted(.relative(presentation: .named)))")
                        .font(.dsSansPt(11))
                        .foregroundStyle(t.text3)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 30)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func iconForType(_ type: SecretRequest.CredentialType) -> String {
        switch type {
        case .apiKey:   "key.fill"
        case .sshKey:   "lock.shield.fill"
        case .token:    "ticket.fill"
        case .password: "lock.fill"
        case .oauth:    "person.fill.badge.plus"
        }
    }
}

private struct PendingSecretRow: View {
    let request: PendingSecretRequest
    let onAuthorize: (String) -> Void
    let onDeny: () -> Void
    @Environment(\.conduitTokens) private var t
    @State private var scopeText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(t.warn)
                    .frame(width: 20, alignment: .center)
                Text("\(request.request.agent) requests \(request.request.credentialType.rawValue)")
                    .font(.dsSansPt(14, weight: .medium))
                    .foregroundStyle(t.text)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Tool: \(request.request.toolName)")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text2)
                Text("Requested scope: \(request.request.requestedScope)")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text2)
            }
            .padding(.leading, 30)

            TextField("Authorize scope (e.g. read:repo)", text: $scopeText)
                .font(.dsMonoPt(13))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(t.surfaceSunk)
                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                .padding(.leading, 30)

            HStack(spacing: 10) {
                Button { onDeny() } label: {
                    Text("Deny")
                        .font(.dsSansPt(14, weight: .medium))
                        .foregroundStyle(t.danger)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                                .strokeBorder(t.danger.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Deny request")

                Button {
                    let scope = scopeText.isEmpty ? request.request.requestedScope : scopeText
                    onAuthorize(scope)
                } label: {
                    Text("Authorize")
                        .font(.dsSansPt(14, weight: .medium))
                        .foregroundStyle(t.accentFg)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(t.accent)
                        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Authorize request")
            }
            .padding(.leading, 30)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct AddSecretSheet: View {
    let vm: SecretsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    private var canAdd: Bool {
        !vm.newSecretName.isEmpty && !vm.newSecretValue.isEmpty
    }

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("add secret", onBack: { dismiss() })

                    sectionHead("CREDENTIAL DETAILS")
                    card {
                        fieldRow(label: "Name") {
                            TextField("e.g. GitHub PAT", text: Binding(
                                get: { vm.newSecretName },
                                set: { vm.newSecretName = $0 }
                            ))
                            .font(.dsSansPt(14))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(t.surfaceSunk)
                            .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                        }
                        hairline
                        fieldRow(label: "Type") {
                            Picker("Type", selection: Binding(
                                get: { vm.newSecretType },
                                set: { vm.newSecretType = $0 }
                            )) {
                                Text("API Key").tag(SecretRequest.CredentialType.apiKey)
                                Text("SSH Key").tag(SecretRequest.CredentialType.sshKey)
                                Text("Token").tag(SecretRequest.CredentialType.token)
                                Text("Password").tag(SecretRequest.CredentialType.password)
                                Text("OAuth").tag(SecretRequest.CredentialType.oauth)
                            }
                            .pickerStyle(.menu)
                            .tint(t.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        hairline
                        fieldRow(label: "Scope") {
                            TextField("e.g. read:repo", text: Binding(
                                get: { vm.newSecretScope },
                                set: { vm.newSecretScope = $0 }
                            ))
                            .font(.dsMonoPt(13))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(t.surfaceSunk)
                            .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                        }
                        hairline
                        fieldRow(label: "Secret value") {
                            SecureField("Secret value", text: Binding(
                                get: { vm.newSecretValue },
                                set: { vm.newSecretValue = $0 }
                            ))
                            .font(.dsMonoPt(13))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(t.surfaceSunk)
                            .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                        }
                    }

                    Text("The secret value is stored on the daemon and never sent to agents. Agents receive only scoped, time-limited access tokens.")
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)

                    Button {
                        Task {
                            await vm.addSecret()
                            dismiss()
                        }
                    } label: {
                        Text("Add secret")
                            .font(.dsSansPt(15, weight: .semibold))
                            .foregroundStyle(canAdd ? t.accentFg : t.text4)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(canAdd ? t.accent : t.surfaceSunk)
                            .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAdd)
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
                    .padding(.bottom, 36)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.dsMonoPt(11, weight: .medium))
                .foregroundStyle(t.text3)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func sectionHead(_ title: String) -> some View {
        Text(title)
            .font(.dsMonoPt(11, weight: .medium))
            .tracking(11 * 0.10)
            .foregroundStyle(t.text3)
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 6)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
            .padding(.horizontal, 18)
    }

    private var hairline: some View {
        DSDivider(.soft, leadingInset: 16)
    }
}
#endif
