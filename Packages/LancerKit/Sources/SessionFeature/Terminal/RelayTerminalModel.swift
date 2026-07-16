#if os(iOS)
import Foundation
import Observation
import TerminalEngine
import SSHTransport

/// Orca-style interactive terminal: lancerd owns the PTY; the phone is a view
/// + input source over the E2E relay (create / subscribe / send / resize).
///
/// Ported from Orca (MIT, Lovecast Inc.) — https://github.com/stablyai/orca
/// Sources: mobile TerminalWebView + runtime terminal.subscribe/send;
/// reimplemented in SwiftUI + SwiftTerm (not xterm WebView).
@MainActor
@Observable
public final class RelayTerminalModel {
    public enum Status: Equatable, Sendable {
        case connecting
        case connected
        case failed(String)
        case closed
    }

    public private(set) var status: Status = .connecting
    public private(set) var title: String
    public private(set) var handle: String?
    public let feedHandle = TerminalFeedHandle()

    private let bridge: E2ERelayBridge
    private let cwd: String?
    private let startupCommand: String?
    private let clientId = UUID().uuidString
    private var streamObserver: NSObjectProtocol?
    private var started = false
    private var lastCols = 80
    private var lastRows = 24
    private var snapshotBuffer = Data()
    private var inSnapshot = false

    public init(
        bridge: E2ERelayBridge,
        title: String,
        cwd: String? = nil,
        startupCommand: String? = nil
    ) {
        self.bridge = bridge
        self.title = title
        self.cwd = cwd
        self.startupCommand = startupCommand
    }

    public func start() async {
        guard !started else { return }
        started = true
        status = .connecting
        observeStreams()
        do {
            let created = try await bridge.relayTerminalCreate(
                TerminalCreateRequest(
                    cwd: cwd,
                    cols: lastCols,
                    rows: lastRows,
                    command: startupCommand
                )
            )
            guard let terminal = created.terminal else {
                throw RelayFSError.host(created.error ?? "terminal.create failed")
            }
            handle = terminal.handle
            title = terminal.title ?? title
            _ = try await bridge.relayTerminalSubscribe(
                handle: terminal.handle,
                clientId: clientId
            )
            status = .connected
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            status = .failed(message)
            started = false
        }
    }

    public func send(_ bytes: [UInt8]) {
        guard let handle, status == .connected else { return }
        let text = String(bytes: bytes, encoding: .utf8) ?? ""
        guard !text.isEmpty else { return }
        Task {
            _ = try? await bridge.relayTerminalSend(handle: handle, text: text)
        }
    }

    public func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        lastCols = cols
        lastRows = rows
        guard let handle, status == .connected else { return }
        Task {
            _ = try? await bridge.relayTerminalResize(handle: handle, cols: cols, rows: rows)
        }
    }

    public func stop() {
        if let observer = streamObserver {
            NotificationCenter.default.removeObserver(observer)
            streamObserver = nil
        }
        if let handle {
            Task { _ = try? await bridge.relayTerminalClose(handle: handle) }
        }
        status = .closed
        started = false
    }

    private func observeStreams() {
        streamObserver = NotificationCenter.default.addObserver(
            forName: .lancerE2ETerminalStream,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            Task { @MainActor in
                self.handleStreamNotification(note)
            }
        }
    }

    private func handleStreamNotification(_ note: Notification) {
        guard let envelope = note.userInfo?["envelope"] as? TerminalStreamEnvelope,
              let machineID = note.userInfo?["machineID"] as? RelayMachineID,
              machineID == bridge.machineID,
              let frameData = Data(base64Encoded: envelope.frame),
              let frame = TerminalStreamCodec.decode(frameData)
        else { return }
        if let handle, envelope.sessionId != handle { return }

        switch frame.opcode {
        case .snapshotStart:
            inSnapshot = true
            snapshotBuffer = Data()
        case .snapshotChunk:
            snapshotBuffer.append(frame.payload)
        case .snapshotEnd:
            inSnapshot = false
            if !snapshotBuffer.isEmpty {
                feedHandle.yield(Array(snapshotBuffer))
                snapshotBuffer = Data()
            }
        case .output:
            if inSnapshot {
                snapshotBuffer.append(frame.payload)
            } else {
                feedHandle.yield(Array(frame.payload))
            }
        case .metadata:
            // Exit / misc — treat non-empty as closed if JSON has exitCode.
            if let obj = try? JSONSerialization.jsonObject(with: frame.payload) as? [String: Any],
               obj["exitCode"] != nil {
                status = .closed
            }
        case .error:
            let msg = String(data: frame.payload, encoding: .utf8) ?? "terminal error"
            status = .failed(msg)
        default:
            break
        }
    }
}
#endif
