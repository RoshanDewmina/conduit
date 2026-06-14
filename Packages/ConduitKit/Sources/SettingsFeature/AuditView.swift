#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import Observation
import ConduitCore
import PersistenceKit
import SSHTransport

@MainActor @Observable
public final class AuditViewModel {
    public var events: [AuditEvent] = []
    public var isLoading = false
    public var errorMessage: String?

    public var verification: AuditVerification?
    public var isVerifying = false
    public var verificationError: String?

    public var entryCount: Int = 0
    public var lastTimestamp: String?
    public var chainValid: Bool?

    private let repository: AuditRepository

    public init(repository: AuditRepository) {
        self.repository = repository
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            events = try await repository.recent(limit: 1_000)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func verifyChain(daemonChannel: DaemonChannel?) async {
        isVerifying = true
        verificationError = nil
        defer { isVerifying = false }
        guard let channel = daemonChannel else {
            verificationError = "No daemon connection"
            return
        }
        do {
            let result = try await channel.verifyAudit()
            verification = result
            chainValid = result.valid
            entryCount = result.entryCount
            lastTimestamp = result.lastTimestamp
        } catch {
            verificationError = error.localizedDescription
        }
    }

    public func exportJSONL(daemonChannel: DaemonChannel?) async -> Data? {
        guard let channel = daemonChannel else {
            errorMessage = "No daemon connection"
            return nil
        }
        do {
            return try await channel.exportAudit()
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public func exportJSON() async -> Data? {
        do {
            return try await repository.exportJSON(limit: 2_000)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

public struct AuditExportDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.json] }
    public var data: Data

    public init(data: Data = Data()) {
        self.data = data
    }

    public init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

public struct AuditView: View {
    @State private var vm: AuditViewModel
    @State private var exportDocument: AuditExportDocument?
    @State private var isExporting = false
    @State private var isExportingJSONL = false
    private let daemonChannel: DaemonChannel?

    public init(viewModel: AuditViewModel, daemonChannel: DaemonChannel? = nil) {
        _vm = State(initialValue: viewModel)
        self.daemonChannel = daemonChannel
    }

    public var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    chainStatusIcon
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audit Chain")
                            .font(.headline)
                        if let count = vm.verification?.entryCount ?? (vm.entryCount > 0 ? vm.entryCount : nil) {
                            Text("\(count) entries")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let ts = vm.verification?.lastTimestamp ?? vm.lastTimestamp {
                            Text("Last: \(ts)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if vm.isVerifying {
                        ProgressView()
                    } else {
                        Button {
                            Task { await vm.verifyChain(daemonChannel: daemonChannel) }
                        } label: {
                            Label("Verify", systemImage: "checkmark.shield")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(vm.chainValid == true ? .green : vm.chainValid == false ? .red : .secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Chain Status")
            }

            if let err = vm.verificationError {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            if let verification = vm.verification, !verification.valid, let brokenAt = verification.brokenAt {
                Section {
                    Label("Chain broken at entry #\(brokenAt)", systemImage: "link.badge.xmark")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            if vm.events.isEmpty, !vm.isLoading {
                ContentUnavailableView(
                    "No audit events yet",
                    systemImage: "checkmark.shield",
                    description: Text("Connection and approval security events will appear here.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(vm.events, id: \.id) { event in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(event.type.rawValue)
                                .font(.caption.weight(.semibold))
                                .textCase(.uppercase)
                            Spacer()
                            Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text("Host: \(event.hostID.uuidString)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        if !event.metadata.isEmpty {
                            Text(Self.metadataText(event.metadata))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Security Audit Log")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task {
                            if let data = await vm.exportJSON() {
                                exportDocument = AuditExportDocument(data: data)
                                isExporting = true
                            }
                        }
                    } label: {
                        Label("Export JSON", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        isExportingJSONL = true
                        Task {
                            if let data = await vm.exportJSONL(daemonChannel: daemonChannel) {
                                exportDocument = AuditExportDocument(data: data)
                                isExporting = true
                            }
                            isExportingJSONL = false
                        }
                    } label: {
                        Label("Export JSONL (hash-chained)", systemImage: "link.badge.plus")
                    }
                    .disabled(isExportingJSONL || daemonChannel == nil)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .overlay {
            if vm.isLoading { ProgressView() }
        }
        .task {
            await vm.load()
            if let channel = daemonChannel {
                await vm.verifyChain(daemonChannel: channel)
            }
        }
        .refreshable { await vm.load() }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument ?? AuditExportDocument(),
            contentType: .json,
            defaultFilename: "conduit-audit-\(Date().formatted(date: .numeric, time: .omitted))"
        ) { _ in
            exportDocument = nil
        }
        .alert("Audit Log", isPresented: .constant(vm.errorMessage != nil), actions: {
            Button("OK") { vm.errorMessage = nil }
        }, message: {
            Text(vm.errorMessage ?? "")
        })
    }

    private var chainStatusIcon: some View {
        Group {
            if vm.chainValid == true {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            } else if vm.chainValid == false {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.red)
            } else {
                Image(systemName: "shield")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.title2)
    }

    private static func metadataText(_ metadata: [String: String]) -> String {
        metadata
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }
}
#endif
