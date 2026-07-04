import Foundation
import Security
import CryptoKit
import LancerCore
import SecurityKit
import OSLog

/// E2E encrypted relay connection between the iOS app and the daemon via a
/// blind WebSocket relay. The relay forwards ciphertext it cannot decrypt.
@MainActor
public final class E2ERelayClient: ObservableObject {

    private nonisolated static let logger = Logger(subsystem: "dev.lancer.mobile", category: "E2ERelayClient")

    private static let udPairingCode = "lancer.relay.pairedCode"
    private static let udPairingPrivKey = "lancer.relay.pairedPrivKey"
    private static let udPairingRelayURL = "lancer.relay.pairedRelayURL"

    @Published public private(set) var connectionState: ConnectionState = .disconnected
    @Published public private(set) var pairingState: PairingState = .unpaired

    public enum ConnectionState: Sendable, Equatable, CustomStringConvertible {
        case disconnected
        case connecting
        case connected
        case reconnecting(attempt: Int)

        public var description: String {
            switch self {
            case .disconnected: return "disconnected"
            case .connecting: return "connecting"
            case .connected: return "connected"
            case .reconnecting(let attempt): return "reconnecting (\(attempt))"
            }
        }
    }

    public enum PairingState: Sendable, Equatable, CustomStringConvertible {
        case unpaired
        case waitingForPeer
        case paired
        case pairingFailed(String)

        public var description: String {
            switch self {
            case .unpaired: return "unpaired"
            case .waitingForPeer: return "waiting for peer"
            case .paired: return "paired"
            case .pairingFailed(let reason): return "failed: \(reason)"
            }
        }
    }

    public struct ReceivedMessage: Sendable {
        public let type: String
        public let payload: Data
    }

    public let machineID: RelayMachineID
    public var relayURL: URL
    public var pairingCode: String
    private var keyPair: PairingCrypto.KeyPair
    private var webSocketTask: URLSessionWebSocketTask?
    private var sessionKey: SymmetricKey?
    private var reconnectTask: Task<Void, Never>?
    private var keepaliveTask: Task<Void, Never>?
    private var messageContinuation: AsyncStream<ReceivedMessage>.Continuation?
    private var reconnectDelay: TimeInterval = 1.0

    /// Incremented on every `connect()`. `URLSessionWebSocketTask.receive`'s
    /// completion-handler callback isn't torn down synchronously by
    /// `webSocketTask?.cancel()` — a message already in flight on a stale
    /// socket can still fire its callback and hop back via `Task { @MainActor
    /// in ... }` AFTER a subsequent `connect()` has already overwritten
    /// `sessionKey` with a new session's key. Without this guard, that stale
    /// callback decrypts using the WRONG (newer) key and fails, which the
    /// daemon logs as "chacha20poly1305: message authentication failed" even
    /// though the current connection's key is perfectly correct — this is
    /// cooperative Task cancellation not actually stopping in-flight
    /// completion-handler-based work, not a real crypto bug. Every receive
    /// callback captures the generation it was armed under and is dropped if
    /// it no longer matches by the time it fires.
    private var connectGeneration: Int = 0

    /// Per-direction replay-resistance sequence for the current pairing
    /// generation — see `SeqFrame`/`ReplaySequencer` below. `sendSeq` is this
    /// client's own outgoing counter; `recv` tracks the highest sequence
    /// accepted from the daemon. Both reset on every new pairing (a fresh
    /// session key = a fresh generation), mirroring the Go daemon's
    /// `e2eRelayClient.sendSeq`/`recv` reset on `peer_joined`.
    private var sendSeq: UInt64 = 0
    private var recv = ReplaySequencer()

    private lazy var messageStream: AsyncStream<ReceivedMessage> = {
        AsyncStream { continuation in
            self.messageContinuation = continuation
        }
    }()

    public var messages: AsyncStream<ReceivedMessage> {
        messageStream
    }

    public init(relayURL: URL, pairingCode: String, machineID: RelayMachineID = RelayMachineID()) {
        self.machineID = machineID
        self.relayURL = relayURL
        self.pairingCode = pairingCode
        self.keyPair = PairingCrypto.generateKeyPair()
    }

    private static func isValidPairingCode(_ code: String) -> Bool {
        code.utf8.count == 6 && code.utf8.allSatisfy { byte in
            byte >= 48 && byte <= 57
        }
    }

    /// The phone's current ephemeral public key (Base64URL). This is the key the
    /// relay forwards to the daemon as `peerPublicKey`; it must be the same key
    /// encoded into the QR the daemon scans, so callers should read this *after*
    /// `beginPairingSession()` and *before* `connect()`.
    public var publicKeyBase64URL: String { keyPair.publicKeyBase64URL }

    /// Rotate to a fresh keypair + single-use pairing code for a new pairing
    /// attempt, and return the new code. Call this before rendering the QR so the
    /// encoded `(code, publicKey)` matches what `connect()` will present. Unlike
    /// the old behaviour, `connect()` no longer rotates the keypair — that would
    /// invalidate a QR already on screen.
    @discardableResult
    public func beginPairingSession() -> String {
        keyPair = PairingCrypto.generateKeyPair()
        let code = PairingCrypto.generatePairingCode()
        pairingCode = code
        return code
    }

    // MARK: - Stored pairing persistence

    public static var hasStoredPairing: Bool {
        UserDefaults.standard.string(forKey: udPairingCode) != nil
    }

    public static func storedPairingCode() -> String? {
        UserDefaults.standard.string(forKey: udPairingCode)
    }

    /// Keychain account for the relay private key.
    private static let kcAccountPrivKey = "lancer.relay.pairedPrivKey"

    /// The relay pairing private key (Base64URL), read from the Keychain. Legacy
    /// installs stored it in `UserDefaults` in plaintext; migrate any such value
    /// into the Keychain on first read and scrub the `UserDefaults` copy.
    public static func storedPairingPrivKey() -> String? {
        if let data = keychainRead(account: kcAccountPrivKey) {
            return Base64URL.encode(data)
        }
        if let legacy = UserDefaults.standard.string(forKey: udPairingPrivKey),
           let data = try? Base64URL.decode(legacy) {
            keychainWrite(data, account: kcAccountPrivKey)
            UserDefaults.standard.removeObject(forKey: udPairingPrivKey)
            return legacy
        }
        return nil
    }

    // MARK: - Keychain (relay private key at rest)
    //
    // The shared SecurityKit `Keychain` is an async actor, but this pairing-
    // persistence API is synchronous, so the (synchronous) SecItem APIs are used
    // directly with the same accessibility class the wrapper uses:
    // whenUnlockedThisDeviceOnly, non-synchronizable (never to iCloud Keychain).

    private static let kcService = "dev.lancer.relay"

    @discardableResult
    private static func keychainWrite(_ data: Data, account: String) -> Bool {
        _ = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("keychainWrite failed: OSStatus \(status, privacy: .public)")
            return false
        }
        return true
    }

    private static func keychainRead(account: String) -> Data? {
        var result: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        guard status == errSecSuccess else {
            // -25300 = errSecItemNotFound (item truly absent), -25308 =
            // errSecInteractionNotAllowed (device locked, WhenUnlocked class
            // key unavailable), -34018 = missing entitlement. The three have
            // completely different fixes — never conflate them.
            logger.error("keychainRead(\(account, privacy: .public)) failed: OSStatus \(status, privacy: .public)")
            print("[E2ERelayClient] keychainRead(\(account)) failed: OSStatus \(status)")
            return nil
        }
        return result as? Data
    }

    /// Diagnostic: every account stored under this app's relay Keychain
    /// service, so an incomplete-pairing state can show whether the private
    /// key exists under a DIFFERENT account (stale machineID) or not at all.
    private static func keychainListAccounts() -> [String] {
        var result: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return ["<list failed: OSStatus \(status)>"]
        }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    private static func keychainDelete(account: String) {
        _ = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }

    public static func storedRelayURL() -> String? {
        UserDefaults.standard.string(forKey: udPairingRelayURL)
    }

    // MARK: - Namespaced (multi-machine) stored pairing persistence
    //
    // Lane 0 of multi-machine relay support: per-machineID persistence,
    // parallel to the singular static API above. Not yet wired into any live
    // call site — a later lane rewires `AppRoot.swift` onto these and deletes
    // the singular API once that rewiring lands.

    /// Keychain account holding the JSON-encoded `[RelayMachineRecord]` index
    /// of all paired machines. Not yet written/read by this lane except by
    /// `RelayMachineMigration`.
    public static let kcAccountMachinesIndex = "lancer.relay.machines.index"

    private static func udMachineCodeKey(_ machineID: RelayMachineID) -> String {
        "lancer.relay.machine.\(machineID.uuidString).code"
    }

    private static func udMachineURLKey(_ machineID: RelayMachineID) -> String {
        "lancer.relay.machine.\(machineID.uuidString).url"
    }

    private static func kcMachinePrivKeyAccount(_ machineID: RelayMachineID) -> String {
        "lancer.relay.machine.\(machineID.uuidString).privKey"
    }

    /// Writes this instance's pairing code, relay URL, and private key under
    /// `self.machineID`-namespaced keys. All-or-nothing: the private key
    /// (Keychain) is written FIRST, and the code/URL (UserDefaults) only if it
    /// succeeded — a key-write failure with the code/URL left behind produces
    /// a machine that hydrates but can never reconnect (seen live on-device
    /// 2026-07-03: code+URL present, key absent, permanent reconnect loop).
    public func persistPairing() {
        guard Self.isValidPairingCode(pairingCode) else {
            Self.logger.error("persistPairing: invalid pairing code shape for machine=\(self.machineID.uuidString, privacy: .public) — NOT persisting pairing")
            return
        }
        guard Self.keychainWrite(keyPair.privateKey.rawRepresentation, account: Self.kcMachinePrivKeyAccount(machineID)) else {
            Self.logger.error("persistPairing: private-key Keychain write failed for machine=\(self.machineID.uuidString, privacy: .public) — NOT persisting code/URL; pairing will not survive relaunch")
            return
        }
        UserDefaults.standard.set(pairingCode, forKey: Self.udMachineCodeKey(machineID))
        UserDefaults.standard.set(relayURL.absoluteString, forKey: Self.udMachineURLKey(machineID))
    }

    public static func hasStoredPairing(machineID: RelayMachineID) -> Bool {
        guard let code = UserDefaults.standard.string(forKey: udMachineCodeKey(machineID)) else { return false }
        return isValidPairingCode(code)
    }

    public static func storedPairingCode(machineID: RelayMachineID) -> String? {
        UserDefaults.standard.string(forKey: udMachineCodeKey(machineID))
    }

    public static func storedPairingPrivKey(machineID: RelayMachineID) -> String? {
        guard let data = keychainRead(account: kcMachinePrivKeyAccount(machineID)) else { return nil }
        return Base64URL.encode(data)
    }

    public static func storedRelayURL(machineID: RelayMachineID) -> String? {
        UserDefaults.standard.string(forKey: udMachineURLKey(machineID))
    }

    /// Deletes all three namespaced entries for `machineID`.
    public static func deleteStoredPairing(machineID: RelayMachineID) {
        UserDefaults.standard.removeObject(forKey: udMachineCodeKey(machineID))
        UserDefaults.standard.removeObject(forKey: udMachineURLKey(machineID))
        keychainDelete(account: kcMachinePrivKeyAccount(machineID))
    }

    /// Same behavior as `restoreStoredPairing()` but reads the namespaced
    /// keys for `self.machineID` instead of the global singular keys.
    ///
    /// Named distinctly from `restoreStoredPairing()` (rather than
    /// overloading it) because that existing instance method already has the
    /// identical `() -> Void` signature — Swift can't disambiguate two
    /// methods that differ only in body, and the singular method must stay
    /// until the later lane that rewires `AppRoot.swift` deletes it.
    /// Returns true only when ALL THREE pieces (code, private key, relay URL)
    /// were present and valid — the only state in which `connect()` can ever
    /// succeed. Callers MUST gate `connect()` on this: the three pieces have
    /// historically diverged on real devices (the machines index + private
    /// keys live in the Keychain and survive an app uninstall; the code + URL
    /// live in UserDefaults and don't — and a Keychain write can fail while
    /// the UserDefaults writes stick). Dialing after a partial restore sent an
    /// EMPTY pairing code and a freshly generated keypair to the relay, which
    /// 400-rejected it in an infinite reconnect loop the UI showed as a
    /// permanently disconnected machine (found live on-device 2026-07-03).
    @discardableResult
    public func restoreNamespacedStoredPairing() -> Bool {
        let storedCode = Self.storedPairingCode(machineID: machineID)
        let storedKey = Self.storedPairingPrivKey(machineID: machineID)
        let storedURL = Self.storedRelayURL(machineID: machineID)
        guard let code = storedCode, let privKeyBase64 = storedKey, let relayURLString = storedURL
        else {
            let detail = "code=\(storedCode != nil) privKey=\(storedKey != nil) url=\(storedURL != nil)"
            Self.logger.error("restoreNamespacedStoredPairing: INCOMPLETE stored pairing for machine=\(self.machineID.uuidString, privacy: .public) — \(detail, privacy: .public); re-pair required")
            print("[E2ERelayClient] INCOMPLETE stored pairing machine=\(machineID.uuidString) \(detail) keychainAccounts=\(Self.keychainListAccounts())")
            return false
        }

        guard Self.isValidPairingCode(code) else {
            Self.logger.error("restoreNamespacedStoredPairing: invalid stored pairing code shape for machine=\(self.machineID.uuidString, privacy: .public); re-pair required")
            print("[E2ERelayClient] INVALID stored pairing code shape machine=\(machineID.uuidString); re-pair required")
            return false
        }

        guard let privKeyData = try? Base64URL.decode(privKeyBase64),
              let privateKey = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privKeyData)
        else {
            Self.logger.error("restoreNamespacedStoredPairing: failed to decode stored private key")
            print("[E2ERelayClient] stored private key UNDECODABLE machine=\(machineID.uuidString); re-pair required")
            return false
        }

        guard let restoredURL = URL(string: relayURLString) else {
            Self.logger.error("restoreNamespacedStoredPairing: invalid stored relay URL for machine=\(self.machineID.uuidString, privacy: .public); re-pair required")
            return false
        }

        self.pairingCode = code
        self.keyPair = PairingCrypto.KeyPair(privateKey: privateKey)
        self.relayURL = restoredURL
        Self.logger.info("restoreNamespacedStoredPairing: restored pairing for relayHost=\(self.relayURL.host ?? "", privacy: .public)")
        return true
    }

    public func connect() {
        // The relay hard-rejects (HTTP 400) any dial without a code, and the
        // client would just retry-loop on it forever. An empty code here means
        // a caller skipped the pairing/restore flow — fail loudly instead.
        guard Self.isValidPairingCode(pairingCode) else {
            Self.logger.error("connect() refused: invalid pairing code shape (machine=\(self.machineID.uuidString, privacy: .public)) — pair or restore first")
            print("[E2ERelayClient] connect() REFUSED: invalid pairing code shape machine=\(machineID.uuidString)")
            return
        }
        Self.logger.info("connect() called, relayHost=\(self.relayURL.host ?? "", privacy: .public) code=\(self.pairingCode, privacy: .private)")
        // Idempotent: tear down any prior connection BEFORE starting a new one.
        // Without this, a second connect() (e.g. a launch-time restore reconnect
        // followed by an explicit re-pair, or the debug auto-pair) leaked the old
        // webSocketTask — its one-shot receive loop kept re-arming on the shared
        // `webSocketTask` property, and the stale `sessionKey` from the abandoned
        // channel made the daemon's encrypted frames fail to decrypt (the relay
        // approval silently never rendered). Cancel the old socket + keepalive and
        // reset pairing state so exactly one channel + one session key is live.
        reconnectTask?.cancel()
        keepaliveTask?.cancel()
        keepaliveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        sessionKey = nil
        sendSeq = 0
        recv.reset()
        pairingState = .unpaired
        connectionState = .connecting
        connectGeneration += 1
        let generation = connectGeneration
        reconnectTask = Task { [weak self] in
            await self?.doConnect(generation: generation)
        }
    }

    public func disconnect() {
        Self.logger.info("disconnect() called")
        connectGeneration += 1
        reconnectTask?.cancel()
        reconnectTask = nil
        keepaliveTask?.cancel()
        keepaliveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
        pairingState = .unpaired
        sessionKey = nil
        sendSeq = 0
        recv.reset()
    }

#if DEBUG
    /// Test-only seam: drive the published pairing/connection states directly so
    /// `ConnectionStateStore`'s derivation and downstream consumers can be
    /// exercised without a live relay — a narrow seam on the real object, not
    /// a parallel fake class (the codebase's established test pattern; see
    /// `E2ERelayClientRestoreTests`).
    public func setStateForTesting(
        pairing: PairingState,
        connection: ConnectionState
    ) {
        connectionState = connection
        pairingState = pairing
    }
#endif

    /// Send an encrypted message to the daemon through the relay.
    public func send(type: String, payload: some Codable) async throws {
        guard let key = sessionKey else {
            throw E2EError.notPaired
        }
        guard let ws = webSocketTask, connectionState == .connected else {
            throw E2EError.notConnected
        }

        let innerMessage = E2EInnerMessage(type: type, payload: payload)
        let innerData = try JSONEncoder().encode(innerMessage)

        let seq = sendSeq
        sendSeq += 1
        let wrapped = try SeqFrame.wrap(seq: seq, body: innerData)

        let encrypted = try PairingCrypto.encrypt(wrapped, using: key)
        let encryptedData = try JSONEncoder().encode(encrypted)
        let encryptedString = String(data: encryptedData, encoding: .utf8) ?? ""

        let relayMsg = RelayOutgoingMessage(
            type: "message",
            target: "daemon",
            payload: encryptedString
        )
        let msgData = try JSONEncoder().encode(relayMsg)
        try await ws.send(.data(msgData))
    }

    // MARK: - Private

    private func doConnect(generation: Int) async {
        guard generation == connectGeneration else {
            Self.logger.info("doConnect: superseded before starting (generation=\(generation, privacy: .public), current=\(self.connectGeneration, privacy: .public)) — skipping")
            return
        }
        var components = URLComponents(url: relayURL, resolvingAgainstBaseURL: false)!
        // The relay endpoint lives at /ws/relay; relayURL is a base with no path
        // (matches the daemon's `<base>/ws/relay` and the relay's registered route).
        let base = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = base.isEmpty ? "/ws/relay" : "/" + base + "/ws/relay"
        components.queryItems = [
            URLQueryItem(name: "role", value: "phone"),
            URLQueryItem(name: "code", value: pairingCode),
            URLQueryItem(name: "publicKey", value: keyPair.publicKeyBase64URL),
        ]

        guard let wsURL = components.url else {
            Self.logger.error("doConnect: failed to construct wsURL from components, path=\(components.path, privacy: .public)")
            connectionState = .disconnected
            return
        }

        // Log host+path only — the query string carries the single-use pairing
        // code and the ephemeral public key, which must not leak to device logs.
        Self.logger.info("doConnect: connecting to \(wsURL.host ?? "", privacy: .public)\(wsURL.path, privacy: .public) role=phone")
        let session = URLSession.shared
        webSocketTask = session.webSocketTask(with: wsURL)
        webSocketTask?.resume()
        Self.logger.info("doConnect: task state after resume: \(self.webSocketTask?.state.rawValue ?? -1, privacy: .public)")

        connectionState = .connected
        pairingState = .waitingForPeer

        listenForMessages(generation: generation)
        startKeepalive()
    }

    private func listenForMessages(generation: Int) {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                let text: String
                switch message {
                case .string(let s):
                    text = s
                case .data(let d):
                    text = String(data: d, encoding: .utf8) ?? ""
                @unknown default:
                    return
                }

                Task { @MainActor in
                    // This closure is armed by a specific connect() generation's
                    // socket. Cooperative Task cancellation doesn't stop an
                    // already in-flight completion-handler receive — a message
                    // that arrived on a since-superseded socket must not be
                    // decrypted against `sessionKey`, which a newer connect()
                    // may have already overwritten. See connectGeneration's doc
                    // comment for the full failure mode this prevents.
                    guard generation == self.connectGeneration else {
                        Self.logger.info("listenForMessages: dropping message from superseded generation=\(generation, privacy: .public), current=\(self.connectGeneration, privacy: .public)")
                        return
                    }
                    self.handleMessage(text)
                    // URLSessionWebSocketTask.receive is one-shot — re-arm to
                    // read the next frame (e.g. peer_joined after waiting).
                    self.listenForMessages(generation: generation)
                }

            case .failure(let error):
                // Don't log the raw error object — its userInfo embeds the full
                // URL (NSErrorFailingURLStringKey), which carries the pairing code.
                if let urlError = error as? URLError {
                    Self.logger.error("receive URLError: code=\(urlError.code.rawValue, privacy: .public) description=\(urlError.localizedDescription, privacy: .public)")
                } else {
                    Self.logger.error("receive failed: \(error.localizedDescription, privacy: .public)")
                }
                Task { @MainActor in
                    guard generation == self.connectGeneration else { return }
                    if let code = self.webSocketTask?.closeCode, code != .invalid {
                        Self.logger.error("receive: ws closeCode=\(code.rawValue, privacy: .public)")
                    }
                    self.handleDisconnect()
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard text.isEmpty == false,
              let data = text.data(using: .utf8),
              let msg = try? JSONDecoder().decode(RelayIncomingMessage.self, from: data)
        else { return }

        switch msg.type {
        case "peer_joined":
            Self.logger.info("handleMessage: peer_joined received, deriving session key")
            guard let peerKey = msg.peerPublicKey else { return }
            do {
                try deriveSessionKey(withPeerPublicKey: peerKey)
                Self.logger.info("handleMessage: session key derived, pairing complete")
                pairingState = .paired
                reconnectDelay = 1.0

                // Namespaced under self.machineID — see persistPairing() below.
                // The old global/singular keys here made every E2ERelayClient
                // instance stomp on the same slot the instant it paired, which
                // breaks as soon as more than one client can pair concurrently.
                persistPairing()

            } catch {
                Self.logger.error("handleMessage: key derivation failed: \(error.localizedDescription, privacy: .public)")
                pairingState = .pairingFailed("Key derivation failed: \(error.localizedDescription)")
            }

        case "peer_left":
            Self.logger.info("handleMessage: peer_left")
            sessionKey = nil
            pairingState = .unpaired

        case "message":
            guard let key = sessionKey, let payload = msg.payload else { return }
            do {
                let frameData = Data(payload.utf8)
                let frame = try JSONDecoder().decode(PairingCrypto.EncryptedFrame.self, from: frameData)
                let plaintext = try PairingCrypto.decrypt(frame, using: key)
                let (seq, body) = try SeqFrame.unwrap(plaintext)
                guard recv.accept(seq) else {
                    Self.logger.error("relay message rejected: replayed or out-of-order sequence \(seq, privacy: .public)")
                    return
                }
                let inner = try JSONDecoder().decode(E2EInnerMessageDecoded.self, from: body)
                messageContinuation?.yield(ReceivedMessage(type: inner.type, payload: body))
            } catch {
                Self.logger.error("relay message decode failed: \(error.localizedDescription, privacy: .public)")
            }

        case "pong":
            break

        case "error":
            Self.logger.error("handleMessage: relay error: \(msg.message ?? "none", privacy: .public)")
            pairingState = .pairingFailed(msg.message ?? "Relay error")

        default:
            break
        }
    }

    private func handleDisconnect() {
        let cc = webSocketTask?.closeCode
        let cr = webSocketTask?.closeReason
        Self.logger.info("handleDisconnect: connection lost, scheduling reconnect in \(self.reconnectDelay)s closeCode=\(cc?.rawValue ?? -1, privacy: .public) closeReason=\(cr?.base64EncodedString() ?? "nil", privacy: .public)")
        connectionState = .disconnected
        pairingState = .unpaired
        sessionKey = nil
        sendSeq = 0
        recv.reset()
        webSocketTask = nil

        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 30)

        connectGeneration += 1
        let generation = connectGeneration
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, Task.isCancelled == false else { return }
            if self.connectionState == .disconnected {
                self.connectionState = .reconnecting(attempt: Int(delay))
                await self.doConnect(generation: generation)
            }
        }
    }

    /// Derive the session key from the daemon's public key.
    ///
    /// MUST match the Go daemon's `deriveSessionKey` in `e2e_client.go`, which on
    /// `peer_joined` calls it with `helperID = "lancer-relay"`,
    /// `helperKeyB64 = <daemon public key>` (its own key) and
    /// `appKeyB64 = <phone public key>`. `PairingCrypto.deriveSessionKey`
    /// reproduces the identical HKDF salt (`SHA256("lancer-pairing:lancer-relay")`)
    /// and info (`"lancer-v1:<daemonKey>:<phoneKey>"`), so both ends derive the
    /// same 32-byte key. The previous bespoke salt/info here did NOT match the
    /// daemon and would silently fail every decrypt.
    private func deriveSessionKey(withPeerPublicKey peerKey: String) throws {
        sessionKey = try PairingCrypto.deriveSessionKey(
            privateKey: keyPair.privateKey,
            peerPublicKeyBase64URL: peerKey,
            helperID: "lancer-relay",
            helperPublicKeyBase64URL: peerKey,
            appPublicKeyBase64URL: keyPair.publicKeyBase64URL
        )
    }

    private func startKeepalive() {
        keepaliveTask?.cancel()
        keepaliveTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let ws = self?.webSocketTask, Task.isCancelled == false else { break }
                let ping = RelayOutgoingMessage(type: "ping")
                if let data = try? JSONEncoder().encode(ping) {
                    try? await ws.send(.data(data))
                }
            }
        }
    }
}

// MARK: - Message Types (package-private)

struct RelayOutgoingMessage: Codable {
    let type: String
    var target: String?
    var payload: String?
}

struct RelayIncomingMessage: Codable {
    let type: String
    var from: String?
    var payload: String?
    var peerPublicKey: String?
    var message: String?
}

struct E2EInnerMessage<T: Codable>: Codable {
    let type: String
    let payload: T
}

// Only `type` is decoded here: the relay client yields the FULL inner plaintext
// ({type, payload:{…}}) as ReceivedMessage.payload, and consumers re-decode the
// typed params via RelayInnerEnvelope<T>. A `payload: Data` field here was a bug —
// JSONDecoder reads Data from a base64 string, but the daemon sends payload as a
// JSON object, so every daemon→phone message failed to decode. Extra JSON keys
// (the payload object) are ignored, so decoding just `type` is correct and robust.
struct E2EInnerMessageDecoded: Codable {
    let type: String
}

// MARK: - Replay resistance (E2E relay)

/// Wraps a relay message body with a monotonically increasing per-direction
/// sequence number BEFORE encryption, so the daemon's AEAD tag covers the
/// counter but the relay (which only ever sees ciphertext) never observes
/// it — a relay-side attacker who can't decrypt still can't selectively
/// drop-and-replay based on a visible sequence. MUST match the Go daemon's
/// `seqFrame`/`wrapSeq`/`unwrapSeq` in `daemon/lancerd/e2e_crypto.go` exactly:
/// a JSON object with `seq` (number) and `body` (the embedded raw JSON
/// message), constructed via `JSONSerialization` rather than `Codable` so
/// `body` round-trips as an embedded JSON value, not a base64 string.
enum SeqFrame {
    enum Error: Swift.Error { case malformedEnvelope }

    static func wrap(seq: UInt64, body: Data) throws -> Data {
        let bodyObject = try JSONSerialization.jsonObject(with: body)
        let envelope: [String: Any] = ["seq": seq, "body": bodyObject]
        return try JSONSerialization.data(withJSONObject: envelope)
    }

    static func unwrap(_ data: Data) throws -> (seq: UInt64, body: Data) {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let seqNumber = obj["seq"] as? NSNumber,
              let bodyObject = obj["body"]
        else {
            throw Error.malformedEnvelope
        }
        let bodyData = try JSONSerialization.data(withJSONObject: bodyObject)
        return (seqNumber.uint64Value, bodyData)
    }
}

/// Rejects a decrypted frame whose sequence number is not strictly greater
/// than the last one accepted for the current pairing generation — the
/// minimum-viable fix for AEAD-with-AAD replay resistance (a WireGuard-style
/// sliding-window bitmap is the fuller version; a bounded reconnect window
/// doesn't need one on top of this). `reset()` is called on every new pairing
/// (a fresh session key = a fresh generation). MUST mirror the Go daemon's
/// `replaySequencer` in `daemon/lancerd/e2e_crypto.go`.
final class ReplaySequencer {
    private var last: UInt64 = 0
    private var initialized = false

    func reset() {
        last = 0
        initialized = false
    }

    func accept(_ seq: UInt64) -> Bool {
        if initialized, seq <= last {
            return false
        }
        last = seq
        initialized = true
        return true
    }
}

// MARK: - Errors

public enum E2EError: Error, LocalizedError {
    case notConnected
    case notPaired
    case encryptFailed
    case decryptFailed
    case timedOut
    case superseded

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to relay"
        case .notPaired: return "Not paired with daemon"
        case .encryptFailed: return "Encryption failed"
        case .decryptFailed: return "Decryption failed"
        case .timedOut: return "The machine didn't respond. Make sure it's online, then try again."
        case .superseded: return "Superseded by a newer request"
        }
    }
}
