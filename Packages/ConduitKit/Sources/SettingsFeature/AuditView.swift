#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import Observation
import ConduitCore
import PersistenceKit

@MainActor @Observable
public final class AuditViewModel {
    public var events: [AuditEvent] = []
    public var isLoading = false
    public var errorMessage: String?

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

    public init(viewModel: AuditViewModel) {
        _vm = State(initialValue: viewModel)
    }

    public var body: some View {
        List {
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
            }
        }
        .overlay {
            if vm.isLoading { ProgressView() }
        }
        .task { await vm.load() }
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

    private static func metadataText(_ metadata: [String: String]) -> String {
        metadata
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }
}
#endif
