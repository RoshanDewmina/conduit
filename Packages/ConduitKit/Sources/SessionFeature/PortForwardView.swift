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
    public let supportsRemoteForwards: Bool = false

    public var addDirection: PortForward.Direction = .local
    public var addLocalPort: String = ""
    public var addRemoteHost: String = "localhost"
    public var addRemotePort: String = ""
    public var addLabel: String = ""
    public var errorMessage: String?
    public var showAddForm: Bool = false

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
            let tunnel: any PortForwardTunnel
            switch forward.direction {
            case .local:
                tunnel = try await session.startLocalPortForward(forward)
            case .remote:
                tunnel = try await session.startRemotePortForward(forward)
            }
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
        if !supportsRemoteForwards { addDirection = .local }
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
        showAddForm = false
    }

    public func removeForward(at index: Int) async {
        await tunnels[index].tunnel?.stop()
        tunnels.remove(at: index)
    }
}

// MARK: - Port Forward Sheet

public struct PortForwardView: View {
    @State private var vm: PortForwardViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    public init(viewModel: PortForwardViewModel) {
        _vm = State(initialValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                t.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Title row
                        HStack {
                            Text("Port Forwarding")
                                .font(.dsDisplayPt(22, weight: .bold))
                                .foregroundStyle(t.text)
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    vm.showAddForm.toggle()
                                }
                            } label: {
                                DSIconView(vm.showAddForm ? .close : .plus, size: 18, color: t.accent)
                                    .frame(width: 36, height: 36)
                                    .background(t.surface, in: Circle())
                                    .overlay(Circle().strokeBorder(t.border, lineWidth: 0.5))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 16)

                        // Add form
                        if vm.showAddForm {
                            sectionHead("New Tunnel")
                            editorCard {
                                // Direction picker
                                HStack(spacing: 8) {
                                    directionChip("Local", .local)
                                    directionChip("Remote", .remote)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                                cardDivider

                                // Ports row
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Local port")
                                            .font(.dsSansPt(11, weight: .medium))
                                            .foregroundStyle(t.text3)
                                        TextField("8080", text: $vm.addLocalPort)
                                            .font(.dsMonoPt(15))
                                            .foregroundStyle(t.text)
                                            .keyboardType(.numberPad)
                                    }
                                    DSIconView(.arrowRight, size: 14, color: t.text3)
                                        .padding(.top, 18)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Remote host")
                                            .font(.dsSansPt(11, weight: .medium))
                                            .foregroundStyle(t.text3)
                                        TextField("localhost", text: $vm.addRemoteHost)
                                            .font(.dsMonoPt(15))
                                            .foregroundStyle(t.text)
                                            .textInputAutocapitalization(.never)
                                    }
                                    Text(":")
                                        .font(.dsMonoPt(15))
                                        .foregroundStyle(t.text3)
                                        .padding(.top, 18)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Port")
                                            .font(.dsSansPt(11, weight: .medium))
                                            .foregroundStyle(t.text3)
                                        TextField("3000", text: $vm.addRemotePort)
                                            .font(.dsMonoPt(15))
                                            .foregroundStyle(t.text)
                                            .keyboardType(.numberPad)
                                            .frame(width: 52)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                                cardDivider

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Label (optional)")
                                        .font(.dsSansPt(11, weight: .medium))
                                        .foregroundStyle(t.text3)
                                    TextField("e.g. dev server", text: $vm.addLabel)
                                        .font(.dsSansPt(15))
                                        .foregroundStyle(t.text)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .padding(.bottom, 12)

                            HStack {
                                Spacer()
                                DSButton("Start Tunnel", variant: .primary, action: {
                                    Task { await vm.addForward() }
                                })
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }

                        // Tunnel list
                        if vm.tunnels.isEmpty && !vm.showAddForm {
                            DSEmptyState(
                                icon: .plug,
                                title: "No forwarded ports",
                                subtitle: "Tap + to add a port tunnel through this SSH session."
                            )
                            .padding(.top, 60)
                        } else if !vm.tunnels.isEmpty {
                            sectionHead("Active Tunnels")
                            VStack(spacing: 0) {
                                ForEach(Array(vm.tunnels.enumerated()), id: \.element.forward.id) { idx, item in
                                    tunnelRow(item: item, idx: idx)
                                    if idx < vm.tunnels.count - 1 {
                                        cardDivider
                                    }
                                }
                            }
                            .background(t.surface, in: RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous)
                                    .strokeBorder(t.border, lineWidth: 0.5)
                            )
                            .padding(.horizontal, 16)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationBarHidden(true)
            .alert("Error", isPresented: .constant(vm.errorMessage != nil)) {
                Button("OK") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    private func tunnelRow(item: (forward: PortForward, tunnel: (any PortForwardTunnel)?), idx: Int) -> some View {
        let isActive = item.tunnel?.isActive == true
        return HStack(spacing: 12) {
            DSStatusDot(tone: isActive ? .ok : .off, pulse: isActive, size: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.forward.displayTitle.isEmpty ? "Tunnel" : item.forward.displayTitle)
                    .font(.dsSansPt(14, weight: .medium))
                    .foregroundStyle(t.text)
                Text("\(item.forward.direction == .local ? "Local" : "Remote") · :\(item.forward.localPort) → \(item.forward.remoteHost):\(item.forward.remotePort)")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }

            Spacer()

            HStack(spacing: 6) {
                Button(isActive ? "Stop" : "Start") {
                    Task {
                        if isActive {
                            await vm.stopTunnel(for: item.forward)
                        } else {
                            await vm.startTunnel(for: item.forward)
                        }
                    }
                }
                .font(.dsSansPt(12, weight: .medium))
                .foregroundStyle(isActive ? t.danger : t.ok)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isActive ? t.dangerSoft : t.okSoft, in: Capsule())

                Button {
                    Task { await vm.removeForward(at: idx) }
                } label: {
                    DSIconView(.close, size: 14, color: t.text3)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func directionChip(_ label: String, _ dir: PortForward.Direction) -> some View {
        let selected = vm.addDirection == dir
        return Text(label)
            .font(.dsSansPt(13, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? t.accentFg : t.text2)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(selected ? t.accent : t.surfaceSunk, in: Capsule())
            .contentShape(Capsule())
            .onTapGesture { vm.addDirection = dir }
            .animation(.easeInOut(duration: 0.15), value: vm.addDirection)
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

    private func editorCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
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
