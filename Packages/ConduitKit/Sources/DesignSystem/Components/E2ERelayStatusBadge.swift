#if os(iOS)
import SwiftUI
import ConduitCore

public struct E2ERelayStatusBadge: View {
    public enum State: Equatable, Sendable {
        case paired
        case connecting
        case degraded
        case direct
        case offline
    }

    public let state: State

    public init(state: State) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 11, design: .monospaced))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.1))
        .cornerRadius(4)
    }

    private var icon: String {
        switch state {
        case .paired:    "lock.shield.fill"
        case .connecting: "antenna.radiowaves.left.and.right"
        case .degraded:  "lock.slash"
        case .direct:    "bolt.horizontal"
        case .offline:   "wifi.slash"
        }
    }

    private var label: String {
        switch state {
        case .paired:    "E2E"
        case .connecting: "Relay"
        case .degraded:  "Weak"
        case .direct:    "SSH"
        case .offline:   "Off"
        }
    }

    private var color: Color {
        switch state {
        case .paired:    .green
        case .connecting: .orange
        case .degraded:  .orange
        case .direct:    .secondary
        case .offline:   .red
        }
    }
}

extension E2ERelayStatusBadge.State {
    public init(relayState: Session.RelayState) {
        switch relayState {
        case .paired:     self = .paired
        case .connecting: self = .connecting
        case .degraded:   self = .degraded
        case .none:       self = .direct
        case .error:      self = .offline
        }
    }
}
#endif
