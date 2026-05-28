#if os(iOS)
import SwiftUI
import UIKit
import ConduitCore
import DesignSystem
import SSHTransport

// MARK: - View model

@MainActor @Observable
public final class PortForwardViewModel {
    public private(set) var tunnels: [(forward: PortForward, tunnel: (any PortForwardTunnel)?)] = []

    // Add form state
    public var addDirection: PortForward.Direction = .local
    public var addLocalPort: String = ""
    public var addRemoteHost: String = "localhost"
    public var addRemotePort: String = ""
    public var addLabel: String = ""
    public var errorMessage: String?

    private let session: SSHSession
    private let hostID: HostID

    public init(session: SSHSession, hostID: HostID) {
        self.session = session
        self.hostID = hostID
    }

    public func startTunnel(for forward: PortForward) async {
        let idx = tunnels.firstIndex { $0.forward.id == forward.id }
        if let i = idx, tunnels[i].tunnel?.isActive == true { return }
        do {
            let tunnel = try await session.startLocalPortForward(forward)
            if let i = idx {
                tunnels[i] = (forward, tunnel)
            } else {
                tunnels.append((forward, tunnel))
            }
        } catch {
            errorMessage = "Failed to start tunnel: \(error.localizedDescription)"
        }
    }

    public func stopTunnel(for forward: PortForward) async {
        guard let i = tunnels.firstIndex(where: { $0.forward.id == forward.id }) else { return }
        await tunnels[i].tunnel?.stop()
        tunnels[i] = (forward, nil)
    }

    public func addForward() async {
        guard let localPort = Int(addLocalPort), localPort > 0, localPort < 65536 else {
            errorMessage = "Local port must be 1–65535"
            return
        }
        guard let remotePort = Int(addRemotePort), remotePort > 0, remotePort < 65536 else {
            errorMessage = "Remote port must be 1–65535"
            return
        }
        let forward = PortForward(
            hostID: hostID,
            direction: addDirection,
            localPort: localPort,
            remoteHost: addRemoteHost.isEmpty ? "localhost" : addRemoteHost,
            remotePort: remotePort,
            label: addLabel
        )
        tunnels.append((forward, nil))
        await startTunnel(for: forward)
        addLocalPort = ""
        addRemotePort = ""
        addLabel = ""
    }

    public func removeForward(at index: Int) async {
        await tunnels[index].tunnel?.stop()
        tunnels.remove(at: index)
    }
}

// MARK: - Port Forward Sheet

public struct PortForwardView: View {
    @State private var vm: PortForwardViewModel
    @State private var showAddForm = false
    @Environment(\.conduitTokens) private var t

    public init(viewModel: PortForwardViewModel) {
        _vm = State(initialValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            List {
                if vm.tunnels.isEmpty {
                    ContentUnavailableView(
                        "No Forwarded Ports",
                        systemImage: "arrow.left.arrow.right",
                        description: Text("Add a tunnel to forward ports through this SSH session.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(Array(vm.tunnels.enumerated()), id: \.element.forward.id) { idx, item in
                        TunnelRow(
                            forward: item.forward,
                            isActive: item.tunnel?.isActive == true,
                            onToggle: {
                                Task {
                                    if item.tunnel?.isActive == true {
                                        await vm.stopTunnel(for: item.forward)
                                    } else {
                                        await vm.startTunnel(for: item.forward)
                                    }
                                }
                            }
                        )
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await vm.removeForward(at: idx) }
                            } label: { Label("Remove", systemImage: "trash") }
                        }
                    }
                }

                if showAddForm {
                    addFormSection
                }
            }
            .navigationTitle("Port Forwarding")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddForm.toggle() } label: {
                        Label(showAddForm ? "Cancel" : "Add", systemImage: showAddForm ? "xmark" : "plus")
                    }
                }
            }
            .alert("Error", isPresented: .constant(vm.errorMessage != nil)) {
                Button("OK") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    private var addFormSection: some View {
        Section("New Tunnel") {
            Picker("Direction", selection: $vm.addDirection) {
                Text("Local").tag(PortForward.Direction.local)
                Text("Remote").tag(PortForward.Direction.remote)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            HStack {
                TextField("Local port", text: $vm.addLocalPort)
                    .keyboardType(.numberPad)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                TerminalSafeTextField(
                    "Remote host",
                    text: $vm.addRemoteHost,
                    font: .monospacedSystemFont(ofSize: 17, weight: .regular)
                )
                Text(":")
                    .foregroundStyle(.secondary)
                TextField("Port", text: $vm.addRemotePort)
                    .keyboardType(.numberPad)
                    .frame(width: 52)
            }
            .font(.system(.body, design: .monospaced))

            TextField("Label (optional)", text: $vm.addLabel)

            Button("Start Tunnel") {
                Task { await vm.addForward() }
                showAddForm = false
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Tunnel row

private struct TunnelRow: View {
    let forward: PortForward
    let isActive: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isActive ? Color.green : Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(forward.displayTitle)
                    .font(.body.weight(.medium))
                Text("\(forward.direction == .local ? "Local" : "Remote") · localhost:\(forward.localPort) → \(forward.remoteHost):\(forward.remotePort)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(isActive ? "Stop" : "Start") { onToggle() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(isActive ? .red : .green)
        }
        .padding(.vertical, 4)
    }
}
#endif
