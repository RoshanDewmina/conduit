#if os(iOS)
import SwiftUI
import DesignSystem
import LancerCore
import SSHTransport

/// Setup-drift findings with a remediation row driven by each finding's
/// `remediation` type. "Apply fix" calls the daemon's `agent.drift.remediate`
/// (safe, idempotent, fail-closed) over the channel and refreshes from the
/// returned report; "Create policy" / "Ignore" are resolved client-side.
struct DriftRemediationView: View {
    let initialReport: DriftReport
    let channel: DaemonChannel?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.lancerTokens) private var t

    @State private var report: DriftReport
    @State private var inFlight: Set<String> = []
    @State private var ignored: Set<String> = []
    @State private var errorMessage: String?

    init(report: DriftReport, channel: DaemonChannel?) {
        self.initialReport = report
        self.channel = channel
        _report = State(initialValue: report)
    }

    private var visibleFindings: [DriftFinding] {
        report.findings.filter { !ignored.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if let errorMessage {
                        DSQuoteBlock(title: "Remediation failed", message: errorMessage, tone: .danger)
                            .padding(.horizontal, 16)
                    }
                    if visibleFindings.isEmpty {
                        Text("No outstanding drift. Every finding is fixed or ignored.")
                            .font(.dsSansPt(13))
                            .foregroundStyle(t.text2)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    } else {
                        ForEach(visibleFindings) { finding in
                            findingRow(finding)
                            DSDivider().padding(.leading, 16)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("Fix drift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        Text("\(visibleFindings.count) finding\(visibleFindings.count == 1 ? "" : "s") across \(report.scanned) instruction files")
            .font(.dsSansPt(13))
            .foregroundStyle(t.text2)
            .padding(.horizontal, 16)
    }

    private func findingRow(_ finding: DriftFinding) -> some View {
        let busy = inFlight.contains(finding.id)
        return VStack(alignment: .leading, spacing: 8) {
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
            actionRow(for: finding, busy: busy)
                .padding(.leading, 18)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func actionRow(for finding: DriftFinding, busy: Bool) -> some View {
        HStack(spacing: 8) {
            switch finding.remediation {
            case .applyFix:
                DSButton(
                    "Apply fix",
                    systemImage: "wand.and.stars",
                    variant: .accent,
                    size: .sm,
                    isLoading: busy
                ) { applyFix(finding) }
                .disabled(busy || channel == nil)
            case .createPolicy:
                DSButton(
                    "Create policy",
                    systemImage: "doc.badge.gearshape",
                    variant: .secondary,
                    size: .sm
                ) { ignore(finding) }
            case .manual:
                Text("Inspect manually")
                    .font(.dsSansPt(11))
                    .foregroundStyle(t.text3)
            }

            DSButton("Ignore", variant: .ghost, size: .sm) { ignore(finding) }
                .disabled(busy)
            Spacer(minLength: 0)
        }
    }

    private func applyFix(_ finding: DriftFinding) {
        guard let channel else { return }
        inFlight.insert(finding.id)
        errorMessage = nil
        Task {
            defer { inFlight.remove(finding.id) }
            do {
                let updated = try await channel.driftRemediate(root: report.root, finding: finding)
                await MainActor.run { report = updated }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func ignore(_ finding: DriftFinding) {
        ignored.insert(finding.id)
    }
}

#Preview {
    let report = DriftReport(
        root: "/Users/dev/repo",
        scanned: 4,
        findings: [
            DriftFinding(
                file: "CLAUDE.md", line: 12, kind: "dead-import", ref: "docs/old.md",
                message: "imported file does not exist", remediation: .applyFix
            ),
            DriftFinding(
                file: "AGENTS.md", line: 3, kind: "dead-link", ref: "RUNBOOK.md",
                message: "linked file does not exist", remediation: .applyFix
            ),
            DriftFinding(
                file: ".claude/rules/go.md", line: 7, kind: "dead-link", ref: "../arch.md",
                message: "linked file does not exist", remediation: .manual
            ),
        ]
    )
    return DriftRemediationView(report: report, channel: nil)
        .lancerTokens(appearance: .dark)
}
#endif
