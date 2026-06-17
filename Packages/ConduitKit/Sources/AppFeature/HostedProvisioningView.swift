#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit

// MARK: - Hosted Provisioning: deploy a runner

enum RunnerSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
}

enum ProvisionStep: Int, CaseIterable {
    case reserve = 0
    case install
    case pair
}

struct HostedProvisioningView: View {
    @State private var selectedRegion = CloudRegion.default.slug
    @State private var selectedSize: RunnerSize = .medium
    @State private var activeStep: ProvisionStep = .install
    @State private var completedSteps: Set<ProvisionStep> = [.reserve]
    @State private var isProvisioning = false
    @State private var showRegionPicker = false

    var onProvision: ((String, RunnerSize) -> Void)?

    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                navBar
                headerSection
                regionPicker
                instanceSizePicker
                Spacer(minLength: 0)
                provisioningSteps
                provisionButton
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
            Text("Provision Hosted")
                .font(.dsSansPt(17, weight: .semibold))
                .foregroundStyle(t.text)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 22)
        .padding(.top, 60)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Deploy a runner")
                .font(.dsDisplayPt(21, weight: .bold))
                .foregroundStyle(t.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 18)
    }

    // MARK: - Region picker

    private var regionPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Region")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)
            Button {
                showRegionPicker = true
            } label: {
                HStack {
                    Text(selectedRegion)
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(t.text3)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(t.surface)
                .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .confirmationDialog("Select region", isPresented: $showRegionPicker, titleVisibility: .visible) {
            ForEach(CloudRegion.catalog) { region in
                Button(region.displayName) {
                    selectedRegion = region.slug
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Instance size

    private var instanceSizePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Instance size")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)
            HStack(spacing: 6) {
                ForEach(RunnerSize.allCases) { size in
                    let isSelected = selectedSize == size
                    Button {
                        selectedSize = size
                    } label: {
                        Text(size.rawValue.capitalized)
                            .font(.dsMonoPt(11))
                            .foregroundStyle(isSelected ? t.text : t.text4)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(t.surface)
                            .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                                    .strokeBorder(isSelected ? t.accent : t.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    // MARK: - Provisioning steps

    private var provisioningSteps: some View {
        VStack(spacing: 2) {
            stepRow(
                label: "Reserving runner instance",
                status: stepStatus(for: .reserve)
            )
            stepRow(
                label: "Installing conduitd runtime",
                status: stepStatus(for: .install)
            )
            stepRow(
                label: "Pairing relay connection",
                status: stepStatus(for: .pair)
            )
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
    }

    private func stepStatus(for step: ProvisionStep) -> StepStatus {
        if completedSteps.contains(step) { return .done }
        if activeStep == step && isProvisioning { return .running }
        if activeStep == step { return .pending }
        return .waiting
    }

    private enum StepStatus { case done, running, pending, waiting }

    @ViewBuilder
    private func stepRow(label: String, status: StepStatus) -> some View {
        HStack(spacing: 10) {
            ZStack {
                switch status {
                case .done:
                    Circle()
                        .fill(t.ok)
                        .frame(width: 18, height: 18)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                case .running:
                    Circle()
                        .strokeBorder(t.accent, lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    ProgressView()
                        .scaleEffect(0.55)
                        .tint(t.accent)
                case .pending:
                    Circle()
                        .strokeBorder(t.accent, lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                case .waiting:
                    Circle()
                        .strokeBorder(t.text4, lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                }
            }
            Text(label)
                .font(.dsMonoPt(11))
                .foregroundStyle(status == .waiting ? t.text4 : t.text2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                .strokeBorder(status == .running ? t.accent : t.border, lineWidth: 1))
    }

    // MARK: - Provision button

    private var provisionButton: some View {
        Button {
            isProvisioning = true
            onProvision?(selectedRegion, selectedSize)
        } label: {
            Text(isProvisioning ? "Provisioning…" : "Provision")
                .font(.dsSansPt(13, weight: .semibold))
                .foregroundStyle(t.accentFg)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
        }
        .background(t.accent)
        .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
        .disabled(isProvisioning)
        .padding(.horizontal, 22)
        .padding(.bottom, 10)
    }
}
#endif
