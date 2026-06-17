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

    public init(viewModel: SecretsViewModel) {
        _vm = State(initialValue: viewModel)
    }

    public var body: some View {
        List {
            if !vm.pendingRequests.isEmpty {
                Section("Pending Requests") {
                    ForEach(vm.pendingRequests) { pending in
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

            Section("Stored Secrets") {
                if vm.secrets.isEmpty, !vm.isLoading {
                    ContentUnavailableView(
                        "No secrets stored",
                        systemImage: "key.fill",
                        description: Text("Add credentials to let agents use them with scoped authorization.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(vm.secrets) { secret in
                        SecretRow(secret: secret) {
                            Task { await vm.delete(secret.id) }
                        }
                    }
                }
            }

            if !vm.secrets.isEmpty {
                Section {
                    Text("\(vm.secrets.count) secret\(vm.secrets.count == 1 ? "" : "s") stored")
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.text3)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Secrets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { vm.showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add secret")
            }
        }
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
}

private struct SecretRow: View {
    let secret: SecretEntry
    let onDelete: () -> Void
    @Environment(\.conduitTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconForType(secret.type))
                    .foregroundStyle(t.accent)
                    .frame(width: 20)
                Text(secret.name)
                    .font(.dsSansPt(15, weight: .medium))
                    .foregroundStyle(t.text1)
                Spacer()
                if secret.useCount > 0 {
                    Text("\(secret.useCount)×")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                }
            }
            if !secret.scope.isEmpty {
                Text("Scope: \(secret.scope)")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text2)
            }
            HStack {
                Text(secret.type.rawValue)
                    .font(.dsMonoPt(10))
                    .foregroundStyle(t.text3)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(t.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                if let lastUsed = secret.lastUsedAt {
                    Text("Last used \(lastUsed.formatted(.relative(presentation: .named)))")
                        .font(.dsSansPt(11))
                        .foregroundStyle(t.text3)
                }
                Spacer()
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                        .font(.dsSansPt(12))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete secret \(secret.name)")
            }
        }
        .padding(.vertical, 4)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "key.fill")
                    .foregroundStyle(.orange)
                Text("\(request.request.agent) requests \(request.request.credentialType.rawValue)")
                    .font(.dsSansPt(14, weight: .medium))
                    .foregroundStyle(t.text1)
            }
            Text("Tool: \(request.request.toolName)")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text2)
            Text("Requested scope: \(request.request.requestedScope)")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text2)
            TextField("Authorize scope (e.g. read:repo)", text: $scopeText)
                .textFieldStyle(.roundedBorder)
                .font(.dsMonoPt(12))
            HStack {
                Button("Deny") { onDeny() }
                    .buttonStyle(.bordered)
                    .tint(.red)
                Button("Authorize") {
                    let scope = scopeText.isEmpty ? request.request.requestedScope : scopeText
                    onAuthorize(scope)
                }
                .buttonStyle(.borderedProminent)
                .tint(t.accent)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AddSecretSheet: View {
    let vm: SecretsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    var body: some View {
        NavigationStack {
            Form {
                Section("Credential Details") {
                    TextField("Name (e.g. GitHub PAT)", text: Binding(
                        get: { vm.newSecretName },
                        set: { vm.newSecretName = $0 }
                    ))
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
                    TextField("Scope (e.g. read:repo)", text: Binding(
                        get: { vm.newSecretScope },
                        set: { vm.newSecretScope = $0 }
                    ))
                    SecureField("Secret value", text: Binding(
                        get: { vm.newSecretValue },
                        set: { vm.newSecretValue = $0 }
                    ))
                }

                Section {
                    Text("The secret value is stored on the daemon and never sent to agents. Agents receive only scoped, time-limited access tokens.")
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.text3)
                }
            }
            .navigationTitle("Add Secret")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            await vm.addSecret()
                            dismiss()
                        }
                    }
                    .disabled(vm.newSecretName.isEmpty || vm.newSecretValue.isEmpty)
                }
            }
        }
    }
}
#endif
