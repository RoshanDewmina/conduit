#if os(iOS)
import SwiftUI
import Observation
import ConduitCore
import AgentKit
import PersistenceKit

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
            case .lightsail:
                provisioner = LightsailProvisioner(accessKey: "", secretKey: "")
            case .orbstack:
                provisioner = OrbstackProvisioner()
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

    public init(hostRepo: HostRepository, onComplete: @escaping (ConduitCore.Host) -> Void, onCancel: @escaping () -> Void) {
        _vm = State(initialValue: ProvisioningWizardViewModel(hostRepo: hostRepo))
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch vm.step {
                case .provider:     providerStep
                case .configure:    configureStep
                case .agent:        agentStep
                case .provisioning: progressStep
                case .done:         doneStep
                }
            }
            .navigationTitle("Set up workspace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private var providerStep: some View {
        Form {
            Section("Cloud Provider") {
                ForEach(ProvisioningPlan.Provider.allCases, id: \.rawValue) { provider in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(provider.displayName).font(.body.weight(.semibold))
                        }
                        Spacer()
                        if vm.plan.provider == provider {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { vm.plan.provider = provider }
                }
            }
            Section {
                Button("Next") { vm.step = .configure }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
        }
    }

    private var configureStep: some View {
        Form {
            Section("Workspace Name") {
                TextField("Name", text: $vm.plan.name)
            }
            if vm.plan.provider == .fly {
                Section("Fly.io API Token") {
                    SecureField("Token (fly tokens create)", text: $vm.flyAPIToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Region") {
                    Picker("Region", selection: $vm.plan.region) {
                        Text("Singapore (sin)").tag("sin")
                        Text("US East (iad)").tag("iad")
                        Text("US West (sjc)").tag("sjc")
                        Text("Europe (ams)").tag("ams")
                        Text("Sydney (syd)").tag("syd")
                    }
                }
                Section("Machine Size") {
                    Picker("Size", selection: $vm.plan.size) {
                        ForEach(ProvisioningPlan.MachineSize.allCases, id: \.rawValue) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            if let err = vm.error {
                Section {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }
            Section {
                Button("Next: Choose agent") { vm.step = .agent }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(vm.plan.name.isEmpty)
            }
            .listRowBackground(Color.clear)
        }
    }

    private var agentStep: some View {
        Form {
            Section("Agent CLI") {
                Picker("Agent", selection: $vm.plan.agentCLI) {
                    ForEach(ProvisioningPlan.AgentCLI.allCases, id: \.rawValue) { agent in
                        Text(agent.displayName).tag(agent)
                    }
                }
                .pickerStyle(.inline)
            }
            Section {
                Button("Provision workspace") {
                    Task { await vm.provision() }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
        }
    }

    private var progressStep: some View {
        VStack(spacing: 20) {
            ProgressView()
            Text("Provisioning...").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(vm.logLines.enumerated()), id: \.offset) { _, line in
                        Text("> \(line)")
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .frame(maxHeight: 300)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding()
        }
    }

    private var doneStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 60)).foregroundStyle(.green)
            Text("Workspace ready!").font(.title2.weight(.semibold))
            if let host = vm.provisionedHost {
                Text("'\(host.name)' at \(host.hostname)").foregroundStyle(.secondary)
            }
            Button("Open session") {
                if let host = vm.provisionedHost { onComplete(host) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}
#endif
