#if os(iOS)
import SwiftUI
import LancerCore

/// Read-only audit tail over `DaemonChannel.tailAudit` (`agent.audit.tail`).
public struct AuditFeedView: View {
    private let limit: Int

    @State private var entries: [AuditLogEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    public init(limit: Int = 100) {
        self.limit = limit
    }

    public var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("cursor.settings.audit.error")
                }
            }

            if entries.isEmpty && errorMessage == nil {
                Section {
                    Text(isLoading ? "Loading…" : "No audit entries.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(entries) { entry in
                    Text(rowText(entry))
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(rowText(entry))
                }
            }
        }
        .navigationTitle("Audit")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .accessibilityIdentifier("cursor.settings.audit-feed")
    }

    private func rowText(_ entry: AuditLogEntry) -> String {
        var parts = [entry.timestamp, entry.action]
        if let agent = entry.agent, !agent.isEmpty { parts.append(agent) }
        if let effect = entry.effect, !effect.isEmpty { parts.append(effect) }
        if let rule = entry.rule, !rule.isEmpty { parts.append(rule) }
        if let command = entry.command, !command.isEmpty { parts.append(command) }
        return parts.joined(separator: "  ")
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            entries = try await GovernanceHostActions.tailAudit(limit: limit)
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }
    }
}
#endif
