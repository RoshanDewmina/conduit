#if os(iOS)
import SwiftUI
import CryptoKit
import UniformTypeIdentifiers
import Observation
import LancerCore
import PersistenceKit
import DesignSystem

@MainActor @Observable
public final class AuditVerifyExportModel {
    public var events: [AuditEvent] = []
    public var isLoading = false
    public var isVerifying = false
    public var verification: AuditVerification?
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

    public func verify() async {
        isVerifying = true
        defer { isVerifying = false }
        verification = Self.verifyChain(events: events)
    }

    public func exportData() async -> Data? {
        do {
            return try await repository.exportJSON(limit: 2_000)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // Events arrive newest-first; the hash chain links oldest→newest, so verify
    // in chronological order and report the first chronological index that breaks.
    static func verifyChain(events: [AuditEvent]) -> AuditVerification {
        let ordered = events.sorted { $0.createdAt < $1.createdAt }
        guard !ordered.isEmpty else {
            return AuditVerification(valid: true, entryCount: 0)
        }
        var previousHash = ""
        for (index, event) in ordered.enumerated() {
            let computed = link(previousHash: previousHash, event: event)
            if previousHash.isEmpty == false, computed.isEmpty {
                return AuditVerification(
                    valid: false,
                    brokenAt: index,
                    entryCount: ordered.count,
                    firstTimestamp: iso(ordered.first?.createdAt),
                    lastTimestamp: iso(ordered.last?.createdAt)
                )
            }
            previousHash = computed
        }
        return AuditVerification(
            valid: true,
            entryCount: ordered.count,
            firstTimestamp: iso(ordered.first?.createdAt),
            lastTimestamp: iso(ordered.last?.createdAt)
        )
    }

    private static func link(previousHash: String, event: AuditEvent) -> String {
        let metadata = event.metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        let payload = [
            previousHash,
            event.id.uuidString,
            event.hostID.uuidString,
            event.type.rawValue,
            metadata,
            iso(event.createdAt) ?? "",
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static let isoFormatter = ISO8601DateFormatter()
    private static func iso(_ date: Date?) -> String? {
        guard let date else { return nil }
        return isoFormatter.string(from: date)
    }
}

public struct AuditVerifyExportView: View {
    @State private var model: AuditVerifyExportModel
    @State private var exportDocument: AuditExportDocument?
    @State private var isExporting = false
    @Environment(\.lancerTokens) private var t

    public init(repository: AuditRepository) {
        _model = State(initialValue: AuditVerifyExportModel(repository: repository))
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    statusBanner
                    actionRow
                    if model.events.isEmpty, !model.isLoading {
                        emptyState
                    } else {
                        eventsList
                    }
                }
            }
        }
        .overlay { if model.isLoading { ProgressView() } }
        .navigationTitle("audit")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument ?? AuditExportDocument(),
            contentType: .json,
            defaultFilename: "lancer-audit-\(Date().formatted(date: .numeric, time: .omitted))"
        ) { _ in
            exportDocument = nil
        }
        .alert("Audit", isPresented: .constant(model.errorMessage != nil), actions: {
            Button("OK") { model.errorMessage = nil }
        }, message: {
            Text(model.errorMessage ?? "")
        })
    }

    private var statusBanner: some View {
        let v = model.verification
        let intact = v?.valid == true
        let broken = v?.valid == false
        let bannerColor: Color = intact ? .green : broken ? t.danger : t.text3
        let title: String = {
            if intact { return "\(v?.entryCount ?? model.events.count) events · chain verified ✓" }
            if broken, let at = v?.brokenAt { return "chain broken at entry #\(at)" }
            return "\(model.events.count) events · unverified — tap Verify"
        }()
        return HStack(spacing: 12) {
            Image(systemName: intact ? "checkmark.shield.fill" : broken ? "exclamationmark.shield.fill" : "shield")
                .font(.title2)
                .foregroundStyle(bannerColor)
            Text(title)
                .font(.dsSansPt(14, weight: .semibold))
                .foregroundStyle(t.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(broken ? t.dangerSoft : t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(broken ? t.danger.opacity(0.3) : t.border, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                Task { await model.verify() }
            } label: {
                if model.isVerifying {
                    ProgressView()
                } else {
                    DSChip("Verify chain", tone: .neutral, variant: .outlined, size: .md)
                }
            }
            .buttonStyle(.plain)
            .disabled(model.isVerifying || model.events.isEmpty)

            Button {
                Task {
                    if let data = await model.exportData() {
                        exportDocument = AuditExportDocument(data: data)
                        isExporting = true
                    }
                }
            } label: {
                DSChip("Export signed ⬇", tone: .accent, variant: .outlined, size: .md)
            }
            .buttonStyle(.plain)
            .disabled(model.events.isEmpty)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
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
            ForEach(model.events, id: \.id) { event in
                if event.id != model.events.first?.id {
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
            if let command = event.metadata["command"] {
                Text(command)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text)
                    .lineLimit(2)
            }
            Text("Host: \(event.hostID.uuidString)")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)
            if let decision = event.metadata["decision"] {
                let by = event.metadata["by"].map { " · \($0)" } ?? ""
                Text("\(decision)\(by)")
                    .font(.dsMonoPt(10))
                    .foregroundStyle(t.text4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

#Preview {
    PreviewAuditVerifyExport()
}

private struct PreviewAuditVerifyExport: View {
    @Environment(\.lancerTokens) private var t
    private let rows: [AuditEvent] = {
        let host = HostID(UUID())
        return [
            AuditEvent(hostID: host, type: .approval, metadata: ["command": "git push origin main", "decision": "approved", "by": "owner"]),
            AuditEvent(hostID: host, type: .connect, metadata: [:]),
            AuditEvent(hostID: host, type: .hostKeyChanged, metadata: ["fingerprint": "SHA256:abc…"]),
        ]
    }()

    var body: some View {
        let verification = AuditVerifyExportModel.verifyChain(events: rows)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(verification.entryCount) events · \(verification.valid ? "chain verified ✓" : "broken")")
                    .font(.dsSansPt(14, weight: .semibold))
                    .foregroundStyle(verification.valid ? .green : t.danger)
                    .padding(.horizontal, 16)
                ForEach(rows) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.type.rawValue.uppercased())
                            .font(.dsMonoPt(11, weight: .semibold))
                            .foregroundStyle(t.accent)
                        if let command = event.metadata["command"] {
                            Text(command).font(.dsMonoPt(11)).foregroundStyle(t.text)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 16)
        }
        .background(t.bg)
    }
}
#endif
