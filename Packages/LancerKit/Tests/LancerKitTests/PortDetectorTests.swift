import Testing
import Foundation
@testable import PreviewKit

@Suite("PortDetector parsing")
struct PortDetectorTests {

    @Test("ss -tlnp output: detects well-known ports")
    func parseSsOutput() {
        let sample = """
        Netid State  Recv-Q Send-Q Local Address:Port Peer Address:Port Process
        tcp   LISTEN 0      128    0.0.0.0:3000      0.0.0.0:*         users:(("node",pid=1234,fd=23))
        tcp   LISTEN 0      128    0.0.0.0:8080      0.0.0.0:*         users:(("python",pid=5678,fd=5))
        """
        let ports = PortDetector.parsePorts(from: sample)
        #expect(ports.contains(3000))
        #expect(ports.contains(8080))
    }

    @Test("lsof -iTCP -sTCP:LISTEN output: detects well-known ports")
    func parseLsofOutput() {
        let sample = """
        COMMAND  PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
        node    1234 dev  20u IPv4 0x1234 0t0      TCP *:5173 (LISTEN)
        """
        let ports = PortDetector.parsePorts(from: sample)
        #expect(ports.contains(5173))
    }

    @Test("unknown ports are ignored")
    func ignoresUnknownPorts() {
        let sample = """
        tcp   LISTEN 0 128 0.0.0.0:9999 0.0.0.0:* users:(("custom",pid=99,fd=3))
        """
        let ports = PortDetector.parsePorts(from: sample)
        #expect(ports.isEmpty)
    }

    @Test("priority order is respected")
    func priorityOrder() {
        let sample = """
        tcp   LISTEN 0 128 0.0.0.0:8080 0.0.0.0:* users:(("python",pid=5678,fd=5))
        tcp   LISTEN 0 128 0.0.0.0:3000 0.0.0.0:* users:(("node",pid=1234,fd=23))
        """
        let ports = PortDetector.parsePorts(from: sample)
        // 3000 should come before 8080 in priority list
        if let idx3000 = ports.firstIndex(of: 3000),
           let idx8080 = ports.firstIndex(of: 8080) {
            #expect(idx3000 < idx8080)
        } else {
            #expect(ports.contains(3000))
            #expect(ports.contains(8080))
        }
    }

    @Test("empty output returns empty array")
    func emptyOutput() {
        let ports = PortDetector.parsePorts(from: "")
        #expect(ports.isEmpty)
    }

    @Test("lsof IPv6 address format: detects port 8000")
    func parseLsofIPv6() {
        let sample = """
        python3 4567 dev 5u IPv6 0xabcd 0t0 TCP *:8000 (LISTEN)
        """
        let ports = PortDetector.parsePorts(from: sample)
        #expect(ports.contains(8000))
    }

    @Test("host preview ports reject invalid input")
    func previewPortValidation() {
        #expect(HostPreviewPort.parse("5173") == 5173)
        #expect(HostPreviewPort.parse("0") == nil)
        #expect(HostPreviewPort.parse("65536") == nil)
        #expect(HostPreviewPort.parse("ssh://host") == nil)
    }

    @Test("only loopback previews stay in the embedded browser")
    func previewURLHandling() {
        #expect(HostPreviewNavigation.isEmbeddedPreviewURL(URL(string: "http://127.0.0.1:5173/")!))
        #expect(HostPreviewNavigation.isEmbeddedPreviewURL(URL(string: "lancer-preview://localhost/")!))
        #expect(!HostPreviewNavigation.isEmbeddedPreviewURL(URL(string: "https://example.com/")!))
        #expect(!HostPreviewNavigation.isEmbeddedPreviewURL(URL(string: "http://192.168.1.2:3000/")!))
    }
}
