#if os(iOS)
import SwiftUI
import LancerCore
import UIKit

/// Read-only audit tail. SSH `DaemonChannel.tailAudit` (`agent.audit.tail`)
/// first, falling back to the relay `agentAuditTail` mirror for a relay-only
/// pairing (no SSH session) — same fallback shape as emergency stop.
public struct AuditFeedView: View {
    private let limit: Int

    @Environment(RelayFleetStore.self) private var relayFleetStore
    @State private var rows: [AuditFeedFormatting.Row] = []
    @State private var expandedIDs: Set<String> = []
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

            if rows.isEmpty && errorMessage == nil {
                Section {
                    Text(isLoading ? "Loading…" : "No audit entries.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(rows) { row in
                    AuditFeedRowView(
                        row: row,
                        isExpanded: expandedIDs.contains(row.id),
                        onToggle: { toggleExpanded(row.id) }
                    )
                }
            }
        }
        .navigationTitle("Audit")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .accessibilityIdentifier("cursor.settings.audit-feed")
    }

    private func toggleExpanded(_ id: String) {
        if expandedIDs.contains(id) {
            expandedIDs.remove(id)
        } else {
            expandedIDs.insert(id)
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let entries = try await GovernanceHostActions.tailAudit(limit: limit, relayFleetStore: relayFleetStore)
            rows = AuditFeedFormatting.rows(fromEntries: entries)
        } catch {
            rows = []
            errorMessage = error.localizedDescription
        }
    }
}

private struct AuditFeedRowView: View {
    let row: AuditFeedFormatting.Row
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.primaryLine)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if row.isParsed, !row.secondaryLine.isEmpty {
                        secondaryLabel
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(row.rawLine)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Copy raw") {
                UIPasteboard.general.string = row.rawLine
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isExpanded ? "Shows raw audit line" : "Double tap to expand raw line")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var secondaryLabel: some View {
        if let effect = row.effectText, row.effectTint != .none {
            let prefix = secondaryPrefix(droppingEffect: effect)
            HStack(spacing: 0) {
                if !prefix.isEmpty {
                    Text(prefix + " · ")
                        .foregroundStyle(.secondary)
                }
                Text(effect)
                    .foregroundStyle(effectColor(row.effectTint))
            }
            .font(.caption)
        } else {
            Text(row.secondaryLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func secondaryPrefix(droppingEffect effect: String) -> String {
        let suffix = " · \(effect)"
        if row.secondaryLine.hasSuffix(suffix) {
            return String(row.secondaryLine.dropLast(suffix.count))
        }
        return row.secondaryLine
    }

    private func effectColor(_ tint: AuditFeedFormatting.EffectTint) -> Color {
        switch tint {
        case .allow: return Color.green.opacity(0.85)
        case .deny: return Color.red.opacity(0.85)
        case .ask: return Color.orange.opacity(0.85)
        case .none: return Color.secondary
        }
    }

    private var accessibilityLabel: String {
        if row.isParsed, !row.secondaryLine.isEmpty {
            return "\(row.primaryLine). \(row.secondaryLine)"
        }
        return row.primaryLine
    }
}
#endif
