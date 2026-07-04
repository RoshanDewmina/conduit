#if os(iOS)
import SwiftUI
import Observation
import LancerCore
import DesignSystem
import SSHTransport

@MainActor @Observable
public final class DoctorViewModel {
    public var report: DoctorReport?
    public var isLoading = false
    public var errorMessage: String?

    private let actions: BridgeSessionActions

    public init(actions: BridgeSessionActions) {
        self.actions = actions
    }

    public func runDoctor() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard actions.isConnected else {
            errorMessage = "No daemon connected"
            return
        }
        do {
            report = try await actions.runDoctor()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

public struct DoctorView: View {
    @State private var vm: DoctorViewModel
    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: DoctorViewModel) {
        _vm = State(initialValue: viewModel)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("lancer doctor", onBack: { dismiss() }) {
                        DSButton("Run", systemImage: "stethoscope", variant: .secondary, size: .sm) {
                            Task { await vm.runDoctor() }
                        }
                        .disabled(vm.isLoading)
                    }

                    if let report = vm.report {
                        reportCard(report)
                        summaryBar(report)
                    } else if vm.isLoading {
                        loadingCard
                    } else if let error = vm.errorMessage {
                        errorCard(error)
                    } else {
                        promptCard
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Report card

    private func reportCard(_ report: DoctorReport) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(report.checks.enumerated()), id: \.element.id) { idx, check in
                if idx > 0 {
                    DSDivider(.soft, leadingInset: 16)
                }
                checkRow(check)
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

    private func checkRow(_ check: DoctorCheckResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.dsSansPt(14))
                .foregroundStyle(check.passed ? t.risk(0) : severityColor(check.severity))
                .frame(width: 20)
                .padding(.top, 1)
                .accessibilityLabel(check.passed ? "Passed" : "Failed")
            VStack(alignment: .leading, spacing: 2) {
                Text(check.name)
                    .font(.dsSansPt(14, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(check.message)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            severityChip(check)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(check.name), \(check.passed ? "passed" : "failed"), \(check.message)")
    }

    @ViewBuilder
    private func severityChip(_ check: DoctorCheckResult) -> some View {
        if !check.passed {
            switch check.severity {
            case .error:
                DSChip("error", tone: .danger, variant: .soft, size: .sm)
            case .warning:
                DSChip("warning", tone: .warn, variant: .soft, size: .sm)
            case .info:
                DSChip("info", tone: .info, variant: .soft, size: .sm)
            }
        }
    }

    private func severityColor(_ severity: DoctorCheckResult.Severity) -> Color {
        switch severity {
        case .error: return t.danger
        case .warning: return t.warn
        case .info: return t.text3
        }
    }

    // MARK: - Summary bar

    private func summaryBar(_ report: DoctorReport) -> some View {
        VStack(spacing: 0) {
            DSDivider(.soft, leadingInset: 0)
            HStack(spacing: 8) {
                if report.allPassed {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.dsSansPt(14))
                        .foregroundStyle(t.risk(0))
                        .accessibilityHidden(true)
                    Text("All checks passed")
                        .font(.dsSansPt(14, weight: .medium))
                        .foregroundStyle(t.risk(0))
                } else {
                    let errCount = report.errors.count
                    let warnCount = report.warnings.count
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.dsSansPt(14))
                        .foregroundStyle(t.warn)
                        .accessibilityHidden(true)
                    Text("\(errCount) error\(errCount == 1 ? "" : "s"), \(warnCount) warning\(warnCount == 1 ? "" : "s")")
                        .font(.dsSansPt(14, weight: .medium))
                        .foregroundStyle(errCount > 0 ? t.danger : t.warn)
                }
                Spacer()
                Text("v\(report.daemonVersion)")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            report.allPassed
                ? "All checks passed, daemon version \(report.daemonVersion)"
                : "\(report.errors.count) error\(report.errors.count == 1 ? "" : "s"), \(report.warnings.count) warning\(report.warnings.count == 1 ? "" : "s"), daemon version \(report.daemonVersion)"
        )
    }

    // MARK: - Prompt / error / loading

    private var promptCard: some View {
        DSEmptyState(
            icon: .shield,
            title: "Run a health check",
            subtitle: "Diagnose daemon setup issues before dispatching work.",
            action: ("Run health check", { Task { await vm.runDoctor() } })
        )
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Running checks…")
                .font(.dsSansPt(14))
                .foregroundStyle(t.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private func errorCard(_ message: String) -> some View {
        DSEmptyState(
            icon: .alertTri,
            title: "Failed to run doctor",
            subtitle: message,
            action: ("Try again", { Task { await vm.runDoctor() } })
        )
    }
}
#endif
