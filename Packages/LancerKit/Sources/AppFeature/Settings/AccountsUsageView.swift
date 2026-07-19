#if os(iOS)
import SwiftUI
import AccountKit
import LancerCore
import SessionFeature

/// Orca-inspired per-vendor accounts + usage screen.
/// Manual switching only — records phone-side intent; Mac credential swap is a future daemon RPC.
public struct AccountsUsageView: View {
    @Environment(RelayFleetStore.self) private var relayFleetStore

    @State private var store = VendorAccountStore()
    @State private var accountsByVendor: [String: [VendorAccount]] = [:]
    @State private var activeByVendor: [String: String] = [:]
    @State private var bridgeStatus: AgentStatusSnapshot?
    @State private var isRefreshing = false
    @State private var statusError: String?

    @State private var addingForVendor: VendorAccountVendor?
    @State private var addLabel = ""
    @State private var addHandle = ""

    @State private var pendingSelect: PendingSelect?
    @State private var showRestartNotice = false

    private struct PendingSelect: Identifiable, Equatable {
        var id: String { "\(vendor)-\(accountID)" }
        let vendor: String
        let accountID: String
    }

    public init() {}

    public var body: some View {
        List {
            ForEach(VendorAccountVendor.allCases, id: \.rawValue) { vendor in
                vendorSection(vendor)
            }
            totalsSection
            footerSection
        }
        .navigationTitle("Accounts & Usage")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("accounts.usage")
        .refreshable { await refreshAll() }
        .task { await refreshAll() }
        .sheet(item: $addingForVendor) { vendor in
            NavigationStack {
                addAccountForm(vendor: vendor)
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog(
            "Restart may be required",
            isPresented: $showRestartNotice,
            titleVisibility: .visible,
            presenting: pendingSelect
        ) { pending in
            Button("Switch anyway") {
                Task { await applySelect(vendor: pending.vendor, accountID: pending.accountID) }
            }
            Button("Cancel", role: .cancel) {
                pendingSelect = nil
            }
        } message: { pending in
            Text("A live \(displayName(for: pending.vendor)) session is running. Switching accounts on the phone records intent only — restart the CLI on your Mac after Mac-side credentials change.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func vendorSection(_ vendor: VendorAccountVendor) -> some View {
        let accounts = accountsByVendor[vendor.rawValue] ?? []
        let activeID = activeByVendor[vendor.rawValue]
        let status = bridgeStatus?.agents.first { $0.agent == vendor.rawValue }

        Section {
            if let status {
                usageRows(status)
            } else {
                Text("Usage unavailable")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if accounts.isEmpty {
                Text("No accounts yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(accounts) { account in
                    accountRow(account, vendor: vendor, isActive: account.id == activeID)
                }
            }

            Button {
                addLabel = ""
                addHandle = ""
                addingForVendor = vendor
            } label: {
                Label("Add account", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("accounts.add.\(vendor.rawValue)")
        } header: {
            Label(vendor.displayName, systemImage: vendor.systemImage)
        } footer: {
            if let active = accounts.first(where: { $0.id == activeID }) {
                Text("Active: \(active.label)\(active.handle.isEmpty ? "" : " · \(active.handle)")")
            } else if !accounts.isEmpty {
                Text("No active account selected.")
            }
        }
    }

    @ViewBuilder
    private func usageRows(_ status: AgentVendorStatus) -> some View {
        LabeledContent("Sessions", value: "\(status.sessionCount)")
        if let running = status.runningCount {
            LabeledContent("Running", value: "\(running)")
        }
        if let usd = status.usageUSD {
            LabeledContent("Usage", value: formatUSD(usd))
        }
        if let period = status.usagePeriod, !period.isEmpty {
            LabeledContent("Period", value: period)
        }
        if let model = status.model, !model.isEmpty {
            LabeledContent("Model", value: model)
        }
        if let loggedIn = status.loggedIn {
            LabeledContent("Logged in", value: loggedIn ? "Yes" : "No")
        }
    }

    private var totalsSection: some View {
        Section("Total") {
            if let total = bridgeStatus?.totalUsageUSD {
                LabeledContent("All vendors", value: formatUSD(total))
            } else {
                Text("No usage totals yet — pull to refresh when a machine is connected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = statusError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var footerSection: some View {
        Section {
            EmptyView()
        } footer: {
            Text("Switching here records which account you intend to use on this phone. Mac-side credential swap arrives with the daemon account RPC — vendor passwords and API keys are never stored on the phone. There is no automatic or rate-limit account rotation.")
        }
    }

    private func accountRow(_ account: VendorAccount, vendor: VendorAccountVendor, isActive: Bool) -> some View {
        Button {
            requestSelect(vendor: vendor.rawValue, accountID: account.id)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.label)
                        .foregroundStyle(.primary)
                    if !account.handle.isEmpty {
                        Text(account.handle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Active")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("accounts.row.\(vendor.rawValue).\(account.id)")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await removeAccount(id: account.id, vendor: vendor.rawValue) }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                requestSelect(vendor: vendor.rawValue, accountID: account.id)
            } label: {
                Label("Use this account", systemImage: "checkmark.circle")
            }
            Button(role: .destructive) {
                Task { await removeAccount(id: account.id, vendor: vendor.rawValue) }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func addAccountForm(vendor: VendorAccountVendor) -> some View {
        Form {
            Section {
                TextField("Label", text: $addLabel)
                TextField("Email or handle", text: $addHandle)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
            } footer: {
                Text("Metadata only — do not enter passwords or API keys.")
            }
        }
        .navigationTitle("Add \(vendor.displayName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { addingForVendor = nil }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    Task { await addAccount(vendor: vendor) }
                }
                .disabled(addLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Actions

    private func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await reloadAccounts()
        await refreshBridgeStatus()
    }

    private func reloadAccounts() async {
        var accounts: [String: [VendorAccount]] = [:]
        var active: [String: String] = [:]
        for vendor in VendorAccountVendor.allCases {
            accounts[vendor.rawValue] = (try? await store.accounts(for: vendor.rawValue)) ?? []
            if let id = try? await store.activeAccountID(for: vendor.rawValue) {
                active[vendor.rawValue] = id
            }
        }
        accountsByVendor = accounts
        activeByVendor = active
    }

    /// Pulls `agent.status` the same way RunningAgentsSection does (relay
    /// `sendStatusQuery`). That is the V1 path — AgentStore.bridgeStatus is
    /// the hosted-SSH twin and is not injected into Workspaces today.
    private func refreshBridgeStatus() async {
        statusError = nil
        guard let machine = relayFleetStore.firstConnectedMachine else {
            statusError = "No connected machine — connect a trusted machine to load usage."
            return
        }
        do {
            bridgeStatus = try await machine.bridge.sendStatusQuery(homeDir: nil)
        } catch {
            statusError = error.localizedDescription
        }
    }

    private func addAccount(vendor: VendorAccountVendor) async {
        let label = addLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let handle = addHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        let account = VendorAccount(vendor: vendor.rawValue, label: label, handle: handle)
        try? await store.add(account)
        addingForVendor = nil
        await reloadAccounts()
    }

    private func removeAccount(id: String, vendor: String) async {
        try? await store.remove(id: id, vendor: vendor)
        await reloadAccounts()
    }

    private func requestSelect(vendor: String, accountID: String) {
        if activeByVendor[vendor] == accountID { return }
        if isVendorRunning(vendor) {
            pendingSelect = PendingSelect(vendor: vendor, accountID: accountID)
            showRestartNotice = true
        } else {
            Task { await applySelect(vendor: vendor, accountID: accountID) }
        }
    }

    private func applySelect(vendor: String, accountID: String) async {
        try? await store.select(id: accountID, vendor: vendor)
        pendingSelect = nil
        await reloadAccounts()
    }

    private func isVendorRunning(_ vendor: String) -> Bool {
        guard let status = bridgeStatus?.agents.first(where: { $0.agent == vendor }) else {
            return false
        }
        return (status.runningCount ?? 0) > 0
    }

    private func displayName(for vendor: String) -> String {
        VendorAccountVendor(rawValue: vendor)?.displayName ?? vendor
    }

    private func formatUSD(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
}

extension VendorAccountVendor: Identifiable {
    public var id: String { rawValue }
}
#endif
