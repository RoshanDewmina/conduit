#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import Observation
import LancerCore
import PersistenceKit
import SSHTransport
import DesignSystem

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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lancerTokens) private var t
    private let daemonChannel: DaemonChannel?

    public init(viewModel: AuditViewModel, daemonChannel: DaemonChannel? = nil) {
        _vm = State(initialValue: viewModel)
        self.daemonChannel = daemonChannel
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("audit log", onBack: { dismiss() }) {
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
                            DSIconButton(.share, accessibilityLabel: "Export") {
                                // Menu handles action
                            }
                        }
                    }

                    chainStatusSection

                    if let err = vm.verificationError {
                        errorBanner(err)
                    }

                    if let verification = vm.verification, !verification.valid, let brokenAt = verification.brokenAt {
                        errorBanner("Chain broken at entry #\(brokenAt)")
                    }

                    if vm.events.isEmpty, !vm.isLoading {
                        emptyState
                    } else {
                        eventsList
                    }
                }
            }
        }
        .navigationBarHidden(true)
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
            defaultFilename: "lancer-audit-\(Date().formatted(date: .numeric, time: .omitted))"
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
        .font(.dsSansPt(20))
        .accessibilityLabel(chainStatusAccessibilityLabel)
    }

    private var chainStatusAccessibilityLabel: String {
        if vm.chainValid == true { return "Audit chain valid" }
        if vm.chainValid == false { return "Audit chain invalid" }
        return "Audit chain status unknown"
    }

    private static func metadataText(_ metadata: [String: String]) -> String {
        metadata
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }

    // MARK: - New helper views

    private var chainStatusSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                chainStatusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text("Audit Chain")
                        .font(.dsSansPt(14, weight: .semibold))
                        .foregroundStyle(t.text)
                    if let count = vm.verification?.entryCount ?? (vm.entryCount > 0 ? vm.entryCount : nil) {
                        Text("\(count) entries")
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text3)
                    }
                    if let ts = vm.verification?.lastTimestamp ?? vm.lastTimestamp {
                        Text("Last: \(ts)")
                            .font(.dsMonoPt(10))
                            .foregroundStyle(t.text4)
                    }
                }
                Spacer()
                if vm.isVerifying {
                    ProgressView()
                } else {
                    Button {
                        Task { await vm.verifyChain(daemonChannel: daemonChannel) }
                    } label: {
                        DSChip("Verify", tone: vm.chainValid == true ? .ok : vm.chainValid == false ? .danger : .neutral, variant: .outlined, size: .sm)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Verify audit chain")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .accessibilityElement(children: .contain)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.dsSansPt(14))
                .foregroundStyle(t.danger)
            Text(message)
                .font(.dsMonoPt(12))
                .foregroundStyle(t.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(t.dangerSoft)
        .overlay(
            Rectangle()
                .strokeBorder(t.danger.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.dsDisplayPt(32))
                .foregroundStyle(t.text4)
            Text("No audit events yet")
                .font(.dsSansPt(14, weight: .semibold))
                .foregroundStyle(t.text)
            Text("Connection and approval security events will appear here.")
                .font(.dsMonoPt(12))
                .foregroundStyle(t.text3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var eventsList: some View {
        VStack(spacing: 0) {
            ForEach(vm.events, id: \.id) { event in
                if event.id != vm.events.first?.id {
                    DSDivider(.soft, leadingInset: 16)
                }
                eventRow(event)
            }
        }
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private func eventRow(_ event: AuditEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(event.type.rawValue)
                    .font(.dsMonoPt(11, weight: .semibold))
                    .foregroundStyle(t.accent)
                    .textCase(.uppercase)
                Spacer()
                Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.dsMonoPt(10))
                    .foregroundStyle(t.text4)
            }
            Text("Host: \(event.hostID.uuidString)")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)
            if !event.metadata.isEmpty {
                Text(Self.metadataText(event.metadata))
                    .font(.dsMonoPt(10))
                    .foregroundStyle(t.text4)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.type.rawValue), \(event.createdAt.formatted(date: .abbreviated, time: .shortened)), host \(event.hostID.uuidString)")
    }
}
#endif
