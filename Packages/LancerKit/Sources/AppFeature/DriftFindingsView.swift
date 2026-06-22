#if os(iOS)
import SwiftUI
import DesignSystem
import LancerCore

/// Read-only list of setup-drift findings for one host, presented from the
/// FleetView "Setup drift" stat card. Phone is summary + drill-in only; the
/// full inspector/repair lives on the Mac app.
struct DriftFindingsView: View {
    let report: DriftReport

    @Environment(\.dismiss) private var dismiss
    @Environment(\.lancerTokens) private var t

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(report.findings.count) finding\(report.findings.count == 1 ? "" : "s") across \(report.scanned) instruction files")
                        .font(.dsSansPt(13))
                        .foregroundStyle(t.text2)
                        .padding(.horizontal, 16)

                    ForEach(report.findings) { finding in
                        findingRow(finding)
                        DSDivider().padding(.leading, 16)
                    }
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("Setup drift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func findingRow(_ finding: DriftFinding) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(t.danger)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(finding.file):\(finding.line)")
                    .font(.dsMonoPt(13, weight: .medium))
                    .foregroundStyle(t.text)
                Text("\(finding.kind) — \(finding.ref)")
                    .font(.dsSansPt(12))
                    .foregroundStyle(t.text2)
                Text(finding.message)
                    .font(.dsSansPt(11))
                    .foregroundStyle(t.text3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}
#endif
