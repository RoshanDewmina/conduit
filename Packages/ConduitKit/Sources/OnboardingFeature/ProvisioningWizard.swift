#if os(iOS)
import SwiftUI
import Observation
import ConduitCore
import AgentKit
import PersistenceKit
import DesignSystem

@MainActor @Observable
public final class ProvisioningWizardViewModel {
    public enum Step { case provider, configure, agent, provisioning, done }

    public var step: Step = .provider
    public var plan = ProvisioningPlan(name: "My Workspace", provider: .fly, region: "sin", agentCLI: .claudeCode)
    public var provisionedHost: ConduitCore.Host?
    public var logLines: [String] = []
    public var error: String?
    public var flyAPIToken: String = ""

    private let hostRepo: HostRepository

    public init(hostRepo: HostRepository) {
        self.hostRepo = hostRepo
    }

    public func provision() async {
        step = .provisioning
        error = nil
        logLines = []

        let log: @Sendable (String) async -> Void = { [weak self] line in
            await MainActor.run { self?.logLines.append(line) }
        }

        do {
            let provisioner: any Provisioner
            switch plan.provider {
            case .fly:
                guard !flyAPIToken.isEmpty else {
                    error = "Enter your Fly.io API token."
                    step = .configure
                    return
                }
                provisioner = FlyProvisioner(apiToken: flyAPIToken)
            #if DEBUG
            case .lightsail:
                provisioner = LightsailProvisioner(accessKey: "", secretKey: "")
            case .orbstack:
                provisioner = OrbstackProvisioner()
            #else
            default:
                error = "This provider is not available in this build."
                step = .configure
                return
            #endif
            }

            let host = try await provisioner.create(plan: plan, log: log)
            try await hostRepo.upsert(host)
            provisionedHost = host
            step = .done
        } catch {
            self.error = error.localizedDescription
            self.step = .configure
        }
    }
}

public struct ProvisioningWizard: View {
    @State private var vm: ProvisioningWizardViewModel
    public var onComplete: (ConduitCore.Host) -> Void
    public var onCancel: () -> Void
    @Environment(\.conduitTokens) private var t

    public init(hostRepo: HostRepository, onComplete: @escaping (ConduitCore.Host) -> Void, onCancel: @escaping () -> Void) {
        _vm = State(initialValue: ProvisioningWizardViewModel(hostRepo: hostRepo))
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                t.bg.ignoresSafeArea()

                Group {
                    switch vm.step {
                    case .provider:     providerStep
                    case .configure:    configureStep
                    case .agent:        agentStep
                    case .provisioning: progressStep
                    case .done:         doneStep
                    }
                }
            }
            .navigationTitle("Set up workspace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(t.accent)
                }
            }
        }
    }

    // MARK: - Provider step

    private var providerStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This wizard provisions a fresh cloud VM with your chosen agent pre-installed.")
                        .font(.dsSansPt(14))
                        .foregroundStyle(t.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("You'll need a Fly.io account and API token. The VM is billed directly by Fly — Conduit never charges you.")
                        .font(.dsSansPt(13))
                        .foregroundStyle(t.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)

                sectionHead("Cloud Provider")
                settingsCard {
                    ForEach(ProvisioningPlan.Provider.allCases, id: \.rawValue) { provider in
                        let isAvailable = provider == .fly
                        HStack {
                            Text(provider.displayName)
                                .font(.dsSansPt(15))
                                .foregroundStyle(isAvailable ? t.text : t.text3)
                            Spacer()
                            if !isAvailable {
                                DSChip("Coming soon", tone: .neutral, variant: .soft, size: .sm)
                            } else if vm.plan.provider == provider {
                                DSIconView(.check, size: 14, color: t.accent)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                        .onTapGesture { if isAvailable { vm.plan.provider = provider } }
                        if provider != ProvisioningPlan.Provider.allCases.last {
                            cardDivider
                        }
                    }
                }
                .padding(.bottom, 24)

                HStack {
                    Spacer()
                    DSButton("Next", variant: .primary, action: { vm.step = .configure })
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Configure step

    private var configureStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionHead("Workspace Name")
                settingsCard {
                    TextField("My Workspace", text: $vm.plan.name)
                        .font(.dsSansPt(15))
                        .foregroundStyle(t.text)
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .padding(.bottom, 16)

                if vm.plan.provider == .fly {
                    sectionHead("Fly.io API Token")
                    settingsCard {
                        SecureField("fly tokens create", text: $vm.flyAPIToken)
                            .font(.dsMonoPt(14))
                            .foregroundStyle(t.text)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .padding(.bottom, 16)

                    sectionHead("Region")
                    settingsCard {
                        let regions: [(String, String)] = [
                            ("Singapore", "sin"), ("US East", "iad"),
                            ("US West", "sjc"), ("Europe", "ams"), ("Sydney", "syd")
                        ]
                        ForEach(regions, id: \.1) { region in
                            HStack {
                                Text(region.0)
                                    .font(.dsSansPt(15))
                                    .foregroundStyle(t.text)
                                Spacer()
                                Text(region.1)
                                    .font(.dsMonoPt(12))
                                    .foregroundStyle(t.text3)
                                if vm.plan.region == region.1 {
                                    DSIconView(.check, size: 14, color: t.accent)
                                        .padding(.leading, 4)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                            .onTapGesture { vm.plan.region = region.1 }
                            if region.1 != "syd" { cardDivider }
                        }
                    }
                    .padding(.bottom, 16)

                    sectionHead("Machine Size")
                    settingsCard {
                        ForEach(ProvisioningPlan.MachineSize.allCases, id: \.rawValue) { size in
                            HStack {
                                Text(size.displayName)
                                    .font(.dsSansPt(15))
                                    .foregroundStyle(t.text)
                                Spacer()
                                if vm.plan.size == size {
                                    DSIconView(.check, size: 14, color: t.accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                            .onTapGesture { vm.plan.size = size }
                            if size != ProvisioningPlan.MachineSize.allCases.last {
                                cardDivider
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }

                if let err = vm.error {
                    HStack(spacing: 6) {
                        DSIconView(.alert, size: 14, color: t.danger)
                        Text(err).font(.dsSansPt(13)).foregroundStyle(t.danger)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }

                HStack {
                    Spacer()
                    DSButton("Next: Choose agent", variant: .primary, action: { vm.step = .agent })
                        .disabled(vm.plan.name.isEmpty)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Agent step

    private var agentStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionHead("Agent CLI")
                settingsCard {
                    ForEach(ProvisioningPlan.AgentCLI.allCases, id: \.rawValue) { agent in
                        HStack {
                            Text(agent.displayName)
                                .font(.dsSansPt(15))
                                .foregroundStyle(t.text)
                            Spacer()
                            if vm.plan.agentCLI == agent {
                                DSIconView(.check, size: 14, color: t.accent)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .onTapGesture { vm.plan.agentCLI = agent }
                        if agent != ProvisioningPlan.AgentCLI.allCases.last {
                            cardDivider
                        }
                    }
                }
                .padding(.bottom, 24)

                HStack {
                    Spacer()
                    DSButton("Provision workspace", variant: .primary, action: {
                        Task { await vm.provision() }
                    })
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Progress step

    private var progressStep: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Provisioning…")
                .font(.dsSansPt(16, weight: .semibold))
                .foregroundStyle(t.text)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(vm.logLines.enumerated()), id: \.offset) { _, line in
                        Text("> \(line)")
                            .font(.dsMonoPt(12))
                            .foregroundStyle(t.termText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 300)
            .background(t.termBg, in: RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous)
                    .strokeBorder(t.termBorder, lineWidth: 0.5)
            )
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Done step

    private var doneStep: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(t.okSoft).frame(width: 80, height: 80)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(t.ok)
            }
            Text("Workspace ready!")
                .font(.dsDisplayPt(22, weight: .bold))
                .foregroundStyle(t.text)
            if let host = vm.provisionedHost {
                Text("'\(host.name)' at \(host.hostname)")
                    .font(.dsSansPt(14))
                    .foregroundStyle(t.text3)
            }
            DSButton("Open session", variant: .primary, action: {
                if let host = vm.provisionedHost { onComplete(host) }
            })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
    }

    // MARK: - Layout helpers

    private func sectionHead(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.dsSansPt(11, weight: .semibold))
            .foregroundStyle(t.text3)
            .tracking(0.5)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
    }

    private func settingsCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(t.surface, in: RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
    }

    private var cardDivider: some View {
        t.border.frame(height: 0.5).padding(.horizontal, 16)
    }
}
#endif
