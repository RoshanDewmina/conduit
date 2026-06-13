#if os(iOS)
import SwiftUI
import ConduitCore
import SSHTransport
import SecurityKit
import TerminalEngine
import DesignSystem

/// A clean, full-fidelity terminal screen built directly on SwiftTerm.
///
/// Unlike the legacy block transcript (`ChatTranscriptView` + `BlockRenderer`),
/// this view feeds **every** PTY byte straight into SwiftTerm — a complete VT
/// emulator — so colour, cursor motion, redraws, progress bars and full-screen
/// TUIs (vim, htop, tmux) all render correctly with zero hand-rolled parsing.
///
/// The "blocks on a real grid" UX is layered on top of this surface in a later
/// pass; this is the rock-solid foundation it sits on.
@MainActor
@Observable
public final class LiveTerminalModel {
    public enum Status: Equatable, Sendable {
        case connecting
        case connected
        case failed(String)
        case closed
    }

    public private(set) var status: Status = .connecting
    public private(set) var title: String

    /// Shared byte conduit consumed by the displayed `RawTerminalView`.
    public let feedHandle = TerminalFeedHandle()

    private let host: Host
    private let credentialProvider: @Sendable () async throws -> SSHCredential
    private let hostKeyStore: HostKeyStore
    private let autoTrustHostKey: Bool
    /// Optional command sent once, immediately after the shell connects. Lets a
    /// debug harness drive a scripted command on launch (e.g. print `tput cols`
    /// to verify the PTY size). `nil` in production — no effect.
    private let autoCommand: String?

    private var session: SSHSession?
    private var shell: SSHShell?
    private var pumpTask: Task<Void, Never>?
    private var started = false

    /// Most recent terminal grid size reported by SwiftTerm. SwiftTerm's
    /// `sizeChanged` typically fires during initial layout — *before* the SSH
    /// handshake completes — so we record it here even when no shell exists yet,
    /// then apply it the moment the PTY opens. Without this the PTY stays at its
    /// open-time size and remote TUIs (vim, htop, Claude Code) draw to the wrong
    /// width and wrap mid-line.
    private var lastCols = 80
    private var lastRows = 24

    public init(
        host: Host,
        credentialProvider: @escaping @Sendable () async throws -> SSHCredential,
        hostKeyStore: HostKeyStore,
        autoTrustHostKey: Bool = false,
        autoCommand: String? = nil
    ) {
        self.host = host
        self.title = host.name
        self.credentialProvider = credentialProvider
        self.hostKeyStore = hostKeyStore
        self.autoTrustHostKey = autoTrustHostKey
        self.autoCommand = autoCommand
    }

    /// Connect, open a PTY shell, and start pumping bytes into SwiftTerm.
    public func start() async {
        guard !started else { return }
        started = true
        status = .connecting
        do {
            let session = SSHSession(host: host)
            let credential = try await credentialProvider()
            try await connect(session: session, credential: credential)
            // Open at the latest size SwiftTerm has reported (defaults until the
            // first layout). Then re-apply it: if `resize` fired while we were
            // connecting, `shell` was nil and the update was dropped — this is
            // where we reconcile so the remote sees the true window size.
            let shell = try await SSHShell.open(session: session, width: lastCols, height: lastRows)
            self.session = session
            self.shell = shell
            try? await shell.resize(cols: lastCols, rows: lastRows)
            self.status = .connected

            if let autoCommand, !autoCommand.isEmpty {
                self.send(Array((autoCommand + "\n").utf8))
            }

            // Pump remote PTY output straight into SwiftTerm. No OSC stripping,
            // no SGR fast-path — SwiftTerm is the single source of truth.
            pumpTask = Task { [weak self, shell] in
                for await chunk in await shell.bytes {
                    self?.feedHandle.yield(chunk)
                }
                self?.status = .closed
            }
        } catch {
            let message = (error as? ConduitError)?.errorDescription ?? error.localizedDescription
            status = .failed(message)
            started = false
        }
    }

    /// Connect, transparently trusting an unknown host key when
    /// `autoTrustHostKey` is set (debug harnesses only). This mirrors the
    /// production flow where the user taps "Trust" in the host-key sheet,
    /// `HostKeyStore.record` is called, and a retry connect hits `.match`.
    /// With the flag off (default), `hostKeyUnknown` propagates so real TOFU
    /// confirmation still happens.
    ///
    /// Defense-in-depth: the auto-trust branch is compiled ONLY under `#if DEBUG`.
    /// In a Release build the catch does not exist, so `hostKeyUnknown` always
    /// propagates and the TOFU prompt is reached — even if `autoTrustHostKey`
    /// were somehow true. Release is structurally incapable of silent auto-trust.
    private func connect(session: SSHSession, credential: SSHCredential) async throws {
        #if DEBUG
        do {
            try await session.connect(credential: credential, hostKeyStore: hostKeyStore)
        } catch let ConduitError.hostKeyUnknown(fingerprint) where autoTrustHostKey {
            try await hostKeyStore.record(hostID: host.id, fingerprint: fingerprint)
            try await session.connect(credential: credential, hostKeyStore: hostKeyStore)
        }
        #else
        try await session.connect(credential: credential, hostKeyStore: hostKeyStore)
        #endif
    }

    /// Forward keyboard bytes to the remote PTY.
    public func send(_ bytes: [UInt8]) {
        guard let shell else { return }
        Task { try? await shell.send(bytes) }
    }

    /// Report a terminal window-size change to the remote PTY. Always records
    /// the size (even before the shell exists) so `start()` can apply it once
    /// the PTY is live; forwards immediately when a shell is already open.
    public func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        lastCols = cols
        lastRows = rows
        guard let shell else { return }
        Task { try? await shell.resize(cols: cols, rows: rows) }
    }

    public func stop() {
        pumpTask?.cancel()
        let shell = self.shell
        let session = self.session
        Task {
            await shell?.close()
            await session?.disconnect()
        }
    }

    /// Convenience for debug harnesses: build a password-auth model from plain
    /// values, so callers don't need to import the SSH/Security modules.
    public static func passwordSession(
        name: String,
        hostname: String,
        port: Int,
        username: String,
        password: String,
        autoTrustHostKey: Bool = false,
        autoCommand: String? = nil
    ) -> LiveTerminalModel {
        let host = Host(name: name, hostname: hostname, port: port, username: username)
        return LiveTerminalModel(
            host: host,
            credentialProvider: { .password(password) },
            hostKeyStore: HostKeyStore(inMemory: true),
            autoTrustHostKey: autoTrustHostKey,
            autoCommand: autoCommand
        )
    }
}

public struct LiveTerminalView: View {
    @State private var model: LiveTerminalModel
    @State private var ctrlLatched = false

    public init(model: LiveTerminalModel) {
        _model = State(initialValue: model)
    }

    private var theme: TerminalTheme { TerminalTheme.current }

    public var body: some View {
        VStack(spacing: 0) {
            header
            terminalSurface
        }
        .background(theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { accessoryRail }
        .task { await model.start() }
        .onDisappear { model.stop() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            DSStatusDot(tone: statusTone, pulse: model.status == .connecting, size: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.title)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.foreground)
                Text(statusLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.foreground.opacity(0.5))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.background)
        .background(Color.black.opacity(0.18))
        .overlay(Rectangle().fill(theme.foreground.opacity(0.08)).frame(height: 0.5), alignment: .bottom)
    }

    // MARK: - Terminal surface

    private var terminalSurface: some View {
        ZStack {
            theme.background
            RawTerminalView(
                feedHandle: model.feedHandle,
                onUserBytes: { bytes in
                    model.send(consumeCtrlLatch(Array(bytes)))
                },
                onResize: { cols, rows in
                    model.resize(cols: cols, rows: rows)
                }
            )

            switch model.status {
            case .connecting:
                statusOverlay(ProgressView().tint(theme.foreground), text: "Connecting…")
            case .failed(let message):
                statusOverlay(Image(systemName: "exclamationmark.triangle"), text: message)
            case .closed:
                statusOverlay(Image(systemName: "bolt.slash"), text: "Session closed")
            case .connected:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func statusOverlay(_ icon: some View, text: String) -> some View {
        VStack(spacing: 10) {
            icon.font(.title2).foregroundStyle(theme.foreground.opacity(0.8))
            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(theme.foreground.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(40)
    }

    // MARK: - Keyboard accessory rail

    private var accessoryRail: some View {
        KeyboardAccessoryRail(ctrlLatched: $ctrlLatched) { bytes in
            model.send(bytes)
        }
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.25))
    }

    // MARK: - Helpers

    /// When the on-screen Ctrl key is latched, fold the next typed letter into
    /// its control code (e.g. latched + "c" → 0x03).
    private func consumeCtrlLatch(_ bytes: [UInt8]) -> [UInt8] {
        guard ctrlLatched, let first = bytes.first else { return bytes }
        ctrlLatched = false
        var outgoing = bytes
        if (0x41...0x5a).contains(first) || (0x61...0x7a).contains(first) {
            outgoing[0] = first & 0x1f
        }
        return outgoing
    }

    private var statusTone: DSStatusDotTone {
        switch model.status {
        case .connecting: return .warn
        case .connected:  return .ok
        case .failed:     return .danger
        case .closed:     return .off
        }
    }

    private var statusLabel: String {
        switch model.status {
        case .connecting:        return "connecting…"
        case .connected:         return "connected"
        case .failed(let msg):   return msg
        case .closed:            return "closed"
        }
    }
}
#endif
