import Testing
import Foundation
@testable import LancerCore

@Suite("RelayConnectionStatusText.footerText")
struct RelayConnectionStatusTextTests {
    @Test("connected with no hosts")
    func connectedNoHosts() {
        let text = RelayConnectionStatusText.footerText(connected: true, hostCount: 0, lastConnectedAt: nil)
        #expect(text == "Relay connected")
    }

    @Test("connected with one host uses singular")
    func connectedOneHost() {
        let text = RelayConnectionStatusText.footerText(connected: true, hostCount: 1, lastConnectedAt: nil)
        #expect(text == "Relay connected · 1 host")
    }

    @Test("connected with multiple hosts uses plural")
    func connectedMultipleHosts() {
        let text = RelayConnectionStatusText.footerText(connected: true, hostCount: 3, lastConnectedAt: nil)
        #expect(text == "Relay connected · 3 hosts")
    }

    @Test("disconnected with no prior connection has no last-seen suffix")
    func disconnectedNeverConnected() {
        let text = RelayConnectionStatusText.footerText(connected: false, hostCount: 1, lastConnectedAt: nil)
        #expect(text == "Relay disconnected")
    }

    @Test("disconnected with a prior connection surfaces a last-seen timestamp")
    func disconnectedWithLastSeen() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let fiveMinutesAgo = now.addingTimeInterval(-300)
        let text = RelayConnectionStatusText.footerText(connected: false, hostCount: 1, lastConnectedAt: fiveMinutesAgo, now: now)
        #expect(text.hasPrefix("Relay disconnected"))
        #expect(text.contains("last seen"))
        #expect(text.contains("5 minutes"))
    }
}
