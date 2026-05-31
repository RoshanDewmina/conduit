#if os(iOS)
import SwiftUI
import Observation
import UniformTypeIdentifiers
import SecurityKit
import ConduitCore
import DesignSystem

// MARK: - KeyImportViewModel

@MainActor @Observable
final class KeyImportViewModel {

    enum Phase: Equatable {
        case idle
        case needsPassphrase   // detected encrypted key — ask for passphrase
        case importing
        case done(fingerprint: String)
        case failed(String)
    }

    var pemText: String = ""
    var passphrase: String = ""
    var label: String = ""
    var phase: Phase = .idle

    var showPassphraseField: Bool {
        if case .needsPassphrase = phase { return true }
        return false
    }

    var canImport: Bool {
        !pemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && phase != .importing
    }

    private let store: KeyStore

    init(store: KeyStore) {
        self.store = store
    }

    func importKey() async {
        let pem = pemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pem.isEmpty else { return }

        // Use passphrase only when the user has typed one AND we already know
        // the key is encrypted. On the first attempt pass nil so the parser can
        // detect encryption and surface the passphrase field first.
        let effectivePassphrase: String? = (showPassphraseField && !passphrase.isEmpty)
            ? passphrase
            : (passphrase.isEmpty ? nil : passphrase)

        let tag = KeyID().uuidString
        let comment = label.trimmingCharacters(in: .whitespacesAndNewlines)

        phase = .importing
        do {
            let info = try await store.importEd25519FromPEM(
                tag: tag,
                pem: pem,
                passphrase: effectivePassphrase,
                comment: comment.isEmpty ? nil : comment
            )
            // Zero-out sensitive fields now that the key is safely in the Keychain.
            // The passphrase was used transiently; the PEM contains the raw private key
            // material — both must be cleared from ViewModel memory immediately.
            passphrase = ""
            pemText = ""
            phase = .done(fingerprint: info.sha256Fingerprint)
        } catch let err as ConduitError {
            let msg = err.errorDescription ?? String(describing: err)
            // "passphrase" appears in both encryptedKeyRequiresPassphrase and
            // wrongPassphrase descriptions, so we key off it for the UX transition.
            if msg.localizedCaseInsensitiveContains("passphrase") && effectivePassphrase == nil {
                phase = .needsPassphrase
            } else {
                phase = .failed(msg)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func reset() {
        pemText = ""
        passphrase = ""
        label = ""
        phase = .idle
    }
}

// MARK: - KeyImportView

/// Sheet that lets the user paste an OpenSSH private key PEM and import it
/// into the local Keychain. If the key is passphrase-protected, a `SecureField`
/// appears after the first parse attempt detects encryption. The passphrase is
/// **never** persisted — it is used transiently only.
public struct KeyImportView: View {
    @State private var vm: KeyImportViewModel
    @State private var showFilePicker = false
    @State private var fileImportError: String?
    var onDismiss: () -> Void

    @Environment(\.conduitTokens) private var t

    public init(store: KeyStore, onDismiss: @escaping () -> Void) {
        _vm = State(initialValue: KeyImportViewModel(store: store))
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            List {
                // MARK: PEM paste area
                Section {
                    ZStack(alignment: .topLeading) {
                        if vm.pemText.isEmpty {
                            Text("-----BEGIN OPENSSH PRIVATE KEY-----\n…")
                                .font(.dsMonoPt(12))
                                .foregroundStyle(t.text3)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $vm.pemText)
                            .font(.dsMonoPt(12))
                            .foregroundStyle(t.text1)
                            .frame(minHeight: 160)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                    }
                } header: {
                    HStack {
                        Text("Private Key (PEM)")
                            .foregroundStyle(t.text2)
                        Spacer()
                        Button {
                            showFilePicker = true
                        } label: {
                            Label("Choose file", systemImage: "doc.badge.plus")
                                .font(.caption)
                                .foregroundStyle(t.accent)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Paste the full contents of your ~/.ssh/id_ed25519 file, including the BEGIN and END lines. Only Ed25519 keys are supported.")
                        if let err = fileImportError {
                            Text(err)
                                .foregroundStyle(t.danger)
                        }
                    }
                    .foregroundStyle(t.text3)
                }
                .listRowBackground(t.surf1)

                // MARK: Optional label
                Section {
                    TextField("e.g. work-laptop", text: $vm.label)
                        .foregroundStyle(t.text1)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Label (optional)")
                        .foregroundStyle(t.text2)
                }
                .listRowBackground(t.surf1)

                // MARK: Passphrase (shown when key is encrypted)
                if vm.showPassphraseField {
                    Section {
                        SecureField("Passphrase", text: $vm.passphrase)
                            .foregroundStyle(t.text1)
                            .textContentType(.password)
                    } header: {
                        Label("Passphrase required", systemImage: "lock.fill")
                            .foregroundStyle(t.accent)
                    } footer: {
                        Text("This key is passphrase-protected. Enter the passphrase to decrypt it for import. The passphrase will not be stored.")
                            .foregroundStyle(t.text3)
                    }
                    .listRowBackground(t.surf1)
                }

                // MARK: Status
                switch vm.phase {
                case .done(let fp):
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Key imported successfully")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(t.text1)
                                Text(fp)
                                    .font(.dsMonoPt(11))
                                    .foregroundStyle(t.text3)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .listRowBackground(t.surf1)

                case .failed(let msg):
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .padding(.top, 2)
                            Text(msg)
                                .font(.callout)
                                .foregroundStyle(t.text2)
                        }
                    }
                    .listRowBackground(t.surf1)

                case .needsPassphrase:
                    Section {
                        Label("Enter passphrase above and tap Import again.", systemImage: "lock.fill")
                            .font(.callout)
                            .foregroundStyle(t.text2)
                    }
                    .listRowBackground(t.surf1)

                case .importing:
                    Section {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Importing…")
                                .foregroundStyle(t.text2)
                        }
                    }
                    .listRowBackground(t.surf1)

                case .idle:
                    EmptyView()
                }

                // MARK: Import button
                Section {
                    Button {
                        Task { await vm.importKey() }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Import Key", systemImage: "square.and.arrow.down")
                                .fontWeight(.semibold)
                                .foregroundStyle(vm.canImport ? t.accent : t.text3)
                            Spacer()
                        }
                    }
                    .disabled(!vm.canImport)
                }
                .listRowBackground(t.surf1)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(t.surf0)
            .navigationTitle("Import Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.reset()
                        onDismiss()
                    }
                    .foregroundStyle(t.text2)
                }
                if case .done = vm.phase {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            vm.reset()
                            onDismiss()
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(t.accent)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.text, .data, .item],
            allowsMultipleSelection: false
        ) { result in
            fileImportError = nil
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    vm.pemText = text
                } catch {
                    fileImportError = "Could not read file: \(error.localizedDescription)"
                }
            case .failure(let error):
                fileImportError = "File import failed: \(error.localizedDescription)"
            }
        }
    }
}

#endif
