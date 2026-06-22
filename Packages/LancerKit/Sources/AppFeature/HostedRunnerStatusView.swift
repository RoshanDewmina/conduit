#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit

// MARK: - Hosted Runner Status

struct HostedRunnerStatusView: View {
    let runnerID: String
    let region: String
    let uptime: String
    let plan: String
    let cpuPercent: Double
    let memUsedGB: Double
    let memTotalGB: Double
    var onViewLogs: (() -> Void)?

    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                navBar
                statusCard
                viewLogsRow
                Spacer(minLength: 0)
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.text)
                    .frame(width: 36, height: 36)
                    .background(t.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                            .strokeBorder(t.border, lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("Hosted runner")
                .font(.dsSansPt(17, weight: .semibold))
                .foregroundStyle(t.text)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 22)
        .padding(.top, 60)
    }

    // MARK: - Status card

    private var statusCard: some View {
        VStack(spacing: 0) {
            // Status header
            HStack(spacing: 8) {
                DSStatusDot(tone: .ok, pulse: true, size: 8)
                Text("runner online")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.ok)
                Spacer()
                Text("ID: \(runnerID)")
                    .font(.dsMonoPt(10))
                    .foregroundStyle(t.text4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(t.surface2)
            .overlay(
                Rectangle()
                    .fill(t.divider)
                    .frame(height: 1),
                alignment: .bottom)

            // Details
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 18) {
                    metricBlock("Region", value: region)
                    metricBlock("Uptime", value: uptime)
                    metricBlock("Plan", value: plan)
                }

                // CPU bar
                resourceBar(
                    label: "CPU",
                    valueText: "\(Int(cpuPercent))%",
                    percent: cpuPercent / 100.0,
                    barTone: cpuPercent > 80 ? .danger : cpuPercent > 60 ? .warn : .ok
                )

                // Memory bar
                resourceBar(
                    label: "MEM",
                    valueText: String(format: "%.1f / %.0f GB", memUsedGB, memTotalGB),
                    percent: memUsedGB / memTotalGB,
                    barTone: (memUsedGB / memTotalGB) > 0.8 ? .danger : (memUsedGB / memTotalGB) > 0.6 ? .warn : .ok
                )
            }
            .padding(16)
        }
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1))
        .padding(.horizontal, 22)
        .padding(.top, 18)
    }

    private func metricBlock(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.dsMonoPt(9.5))
                .foregroundStyle(t.text4)
            Text(value)
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func resourceBar(
        label: String,
        valueText: String,
        percent: Double,
        barTone: DSChipTone
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.dsMonoPt(9.5))
                    .foregroundStyle(t.text4)
                Spacer()
                Text(valueText)
                    .font(.dsMonoPt(9.5))
                    .foregroundStyle(t.text4)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(t.surfaceSunk).frame(height: 4)
                    Capsule()
                        .fill(barFillColor(barTone))
                        .frame(width: geo.size.width * min(max(percent, 0), 1), height: 4)
                        .animation(.easeInOut(duration: 0.2), value: percent)
                }
            }
            .frame(height: 4)
        }
    }

    private func barFillColor(_ tone: DSChipTone) -> Color {
        switch tone {
        case .ok:     return t.ok
        case .warn:   return t.warn
        case .danger: return t.danger
        default:      return t.ok
        }
    }

    // MARK: - View logs row

    private var viewLogsRow: some View {
        Button {
            onViewLogs?()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.text3)
                Text("View logs")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text2)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(t.text3)
            }
            .padding(12)
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22)
        .padding(.top, 10)
    }
}
#endif
