import SwiftUI
import ConduitCore

struct ApprovalDetailView: View {
    let item: WatchApprovalTransfer
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Risk + agent header
                HStack(spacing: 5) {
                    Circle()
                        .fill(riskColor(item.risk))
                        .frame(width: 7, height: 7)
                    Text(riskLabel(item.risk))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(riskColor(item.risk))
                    Spacer()
                    Text(item.agent)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Command block
                if let cmd = item.command {
                    Text(cmd)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                } else {
                    Text(item.kind.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // cwd
                Text(item.cwd)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)

                // Decision buttons
                VStack(spacing: 6) {
                    Button {
                        store.decideApproval(item, approved: true)
                        dismiss()
                    } label: {
                        Label("Allow", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button(role: .destructive) {
                        store.decideApproval(item, approved: false)
                        dismiss()
                    } label: {
                        Label("Reject", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Approval")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shared helpers (package-internal)

func riskColor(_ risk: Int) -> Color {
    switch risk {
    case 0: .green
    case 1: .yellow
    case 2: .orange
    default: .red
    }
}

func riskLabel(_ risk: Int) -> String {
    switch risk {
    case 0: "low"
    case 1: "medium"
    case 2: "HIGH"
    default: "CRITICAL"
    }
}

func timeAgo(from date: Date) -> String {
    let secs = Int(-date.timeIntervalSinceNow)
    if secs < 60 { return "\(max(secs, 0))s" }
    let mins = secs / 60
    if mins < 60 { return "\(mins)m" }
    return "\(mins / 60)h"
}
