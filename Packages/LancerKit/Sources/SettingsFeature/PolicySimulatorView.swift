#if os(iOS)
import SwiftUI
import LancerCore
import DesignSystem

public struct PolicySimulatorView: View {
    let initialYAML: String
    let simulate: (@Sendable (_ yaml: String, _ periodDays: Int) async throws -> PolicySimulation)?

    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss

    @State private var yamlText: String
    @State private var simulation: PolicySimulation?
    @State private var isRunning = false
    @State private var statusMessage: String?
    @State private var periodDays: Int = 7

    public init(
        yaml: String,
        simulate: (@Sendable (_ yaml: String, _ periodDays: Int) async throws -> PolicySimulation)? = nil
    ) {
        self.initialYAML = yaml
        _yamlText = State(initialValue: yaml)
        self.simulate = simulate
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("policy simulator", onBack: { dismiss() })
                    headerSection
                    periodSelector
                    yamlEditor
                    runButton
                    if let sim = simulation {
                        resultsSection(sim)
                    } else if let msg = statusMessage {
                        Text(msg)
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text3)
                            .padding(.horizontal, 18)
                            .padding(.top, 12)
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SIMULATE PROPOSED POLICY")
                .font(.dsMonoPt(10, weight: .semibold))
                .tracking(10 * 0.12)
                .foregroundStyle(t.text3)

            Text("Replay the last \(periodDays) days of audit history against a proposed policy to see what would have been auto-approved, asked, or denied.")
                .font(.dsSansPt(13))
                .foregroundStyle(t.text2)
                .lineSpacing(2)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Period selector

    private var periodSelector: some View {
        HStack(spacing: 8) {
            ForEach([3, 7, 14, 30], id: \.self) { days in
                DSChip(
                    "\(days)d",
                    tone: periodDays == days ? .accent : .neutral,
                    variant: periodDays == days ? .default : .outlined,
                    size: .sm
                )
                .onTapGesture { periodDays = days }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    // MARK: - YAML editor

    private var yamlEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PROPOSED POLICY")
                .font(.dsMonoPt(10, weight: .semibold))
                .tracking(10 * 0.12)
                .foregroundStyle(t.text3)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

            TextEditor(text: $yamlText)
                .font(.dsMonoPt(12))
                .foregroundStyle(t.termText)
                .scrollContentBackground(.hidden)
                .background(t.termSurface)
                .frame(minHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: t.r1, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r1, style: .continuous)
                        .strokeBorder(t.termBorder, lineWidth: 1)
                )
                .padding(.horizontal, 18)
        }
    }

    // MARK: - Run button

    private var runButton: some View {
        DSButton(
            isRunning ? "Simulating…" : "Run simulation",
            variant: .primary,
            size: .md,
            mono: true,
            isLoading: isRunning,
            fullWidth: true
        ) {
            Task { await runSimulation() }
        }
        .disabled(isRunning)
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    // MARK: - Results

    private func resultsSection(_ sim: PolicySimulation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary
            DSQuoteBlock(
                title: "Result",
                tags: ["\(sim.periodDays)d"],
                message: sim.summary,
                tone: .accent
            )

            // Outcome bar
            if sim.totalActions > 0 {
                outcomeBar(sim)
            }

            // Counts
            countsRow(sim)

            // Risk distribution
            if !sim.riskDistribution.isEmpty {
                riskSection(sim)
            }

            // Rule hits
            if !sim.ruleHits.isEmpty {
                ruleHitsSection(sim)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 32)
    }

    private func outcomeBar(_ sim: PolicySimulation) -> some View {
        let total = max(sim.totalActions, 1)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(t.ok)
                    .frame(width: CGFloat(sim.autoApproved) / CGFloat(total) * 200, height: 8)
                Rectangle()
                    .fill(t.warn)
                    .frame(width: CGFloat(sim.asked) / CGFloat(total) * 200, height: 8)
                Rectangle()
                    .fill(t.danger)
                    .frame(width: CGFloat(sim.denied) / CGFloat(total) * 200, height: 8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text("\(sim.totalActions) total actions evaluated")
                .font(.dsMonoPt(10))
                .foregroundStyle(t.text4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func countsRow(_ sim: PolicySimulation) -> some View {
        HStack(spacing: 12) {
            DSChip("\(sim.autoApproved) auto-approve", tone: .ok, variant: .solid, size: .sm)
            DSChip("\(sim.asked) ask", tone: .warn, variant: .solid, size: .sm)
            DSChip("\(sim.denied) deny", tone: .danger, variant: .solid, size: .sm)
        }
    }

    private func riskSection(_ sim: PolicySimulation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RISK DISTRIBUTION")
                .font(.dsMonoPt(10, weight: .semibold))
                .tracking(10 * 0.12)
                .foregroundStyle(t.text3)

            HStack(spacing: 8) {
                ForEach(["low", "medium", "high", "critical"], id: \.self) { label in
                    if let count = sim.riskDistribution[label], count > 0 {
                        DSChip("\(count) \(label)", tone: riskTone(label), variant: .soft, size: .sm)
                    }
                }
            }
        }
    }

    private func ruleHitsSection(_ sim: PolicySimulation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOP RULE HITS")
                .font(.dsMonoPt(10, weight: .semibold))
                .tracking(10 * 0.12)
                .foregroundStyle(t.text3)

            VStack(spacing: 0) {
                ForEach(Array(sim.ruleHits.prefix(8).enumerated()), id: \.offset) { idx, hit in
                    if idx > 0 {
                        Rectangle()
                            .fill(t.divider)
                            .frame(height: 1)
                            .padding(.leading, 12)
                    }
                    ruleHitRow(hit)
                }
            }
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r1, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r1, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
        }
    }

    private func ruleHitRow(_ hit: PolicySimulation.RuleHit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(hit.ruleID)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                Spacer()
                DSChip("\(hit.count)×", tone: effectTone(hit.effect), variant: .mono, size: .sm)
            }

            if !hit.sampleCommands.isEmpty {
                ForEach(hit.sampleCommands.prefix(2), id: \.self) { cmd in
                    DSQuoteBlock(title: "", tags: [], message: cmd, tone: .neutral)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func runSimulation() async {
        isRunning = true
        defer { isRunning = false }

        guard let simulate else {
            // No daemon channel wired — show an empty local placeholder result.
            statusMessage = "Connect an SSH session to simulate against real audit history."
            simulation = PolicySimulation(
                generatedAt: ISO8601DateFormatter().string(from: .now),
                periodDays: periodDays,
                totalActions: 0,
                autoApproved: 0,
                asked: 0,
                denied: 0,
                ruleHits: [],
                riskDistribution: [:]
            )
            return
        }

        statusMessage = "Sending to daemon…"
        do {
            simulation = try await simulate(yamlText, periodDays)
            statusMessage = nil
        } catch {
            simulation = nil
            statusMessage = "Simulation failed: \(error.localizedDescription)"
        }
    }

    private func riskTone(_ label: String) -> DSChipTone {
        switch label {
        case "critical": return .danger
        case "high":     return .orange
        case "medium":   return .warn
        default:         return .ok
        }
    }

    private func effectTone(_ effect: String) -> DSChipTone {
        switch effect {
        case "allow": return .ok
        case "ask":   return .warn
        case "deny":  return .danger
        default:      return .neutral
        }
    }
}

#endif
