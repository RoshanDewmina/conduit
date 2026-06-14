import Foundation
import CryptoKit
import ConduitCore
import SecurityKit

/// E2E encrypted relay connection between the iOS app and the daemon via a
/// blind WebSocket relay. The relay forwards ciphertext it cannot decrypt.
@MainActor
public final class E2ERelayClient: ObservableObject {

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

    public var relayURL: URL
    public var pairingCode: String
    private var keyPair: PairingCrypto.KeyPair
    private var webSocketTask: URLSessionWebSocketTask?
    private var sessionKey: SymmetricKey?
    private var reconnectTask: Task<Void, Never>?
    private var keepaliveTask: Task<Void, Never>?
    private var messageContinuation: AsyncStream<ReceivedMessage>.Continuation?
    private var reconnectDelay: TimeInterval = 1.0

    private lazy var messageStream: AsyncStream<ReceivedMessage> = {
        AsyncStream { continuation in
            self.messageContinuation = continuation
        }
    }()

    public var messages: AsyncStream<ReceivedMessage> {
        messageStream
    }

    public init(relayURL: URL, pairingCode: String) {
        self.relayURL = relayURL
        self.pairingCode = pairingCode
        self.keyPair = PairingCrypto.generateKeyPair()
    }

    public func connect() {
        keyPair = PairingCrypto.generateKeyPair()
        connectionState = .connecting
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            await self?.doConnect()
        }
    }

    public func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        keepaliveTask?.cancel()
        keepaliveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
        pairingState = .unpaired
        sessionKey = nil
    }

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

        let encrypted = try PairingCrypto.encrypt(innerData, using: key)
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

    private func doConnect() async {
        var components = URLComponents(url: relayURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "role", value: "phone"),
            URLQueryItem(name: "code", value: pairingCode),
            URLQueryItem(name: "publicKey", value: keyPair.publicKeyBase64URL),
        ]

        guard let wsURL = components.url else {
            connectionState = .disconnected
            return
        }

        let session = URLSession.shared
        webSocketTask = session.webSocketTask(with: wsURL)
        webSocketTask?.resume()

        connectionState = .connected
        pairingState = .waitingForPeer

        listenForMessages()
        startKeepalive()
    }

    private func listenForMessages() {
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
                    self.handleMessage(text)
                }

            case .failure:
                Task { @MainActor in
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
            guard let peerKey = msg.peerPublicKey else { return }
            do {
                try deriveSessionKey(withPeerPublicKey: peerKey)
                pairingState = .paired
                reconnectDelay = 1.0
            } catch {
                pairingState = .pairingFailed("Key derivation failed: \(error.localizedDescription)")
            }

        case "peer_left":
            sessionKey = nil
            pairingState = .unpaired

        case "message":
            guard let key = sessionKey, let payload = msg.payload else { return }
            do {
                let frameData = Data(payload.utf8)
                let frame = try JSONDecoder().decode(PairingCrypto.EncryptedFrame.self, from: frameData)
                let plaintext = try PairingCrypto.decrypt(frame, using: key)
                let inner = try JSONDecoder().decode(E2EInnerMessageDecoded.self, from: plaintext)
                messageContinuation?.yield(ReceivedMessage(type: inner.type, payload: plaintext))
            } catch {
                print("E2E relay decrypt failed: \(error)")
            }

        case "pong":
            break

        case "error":
            pairingState = .pairingFailed(msg.message ?? "Relay error")

        default:
            break
        }
    }

    private func handleDisconnect() {
        connectionState = .disconnected
        pairingState = .unpaired
        sessionKey = nil
        webSocketTask = nil

        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 30)

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, Task.isCancelled == false else { return }
            if self.connectionState == .disconnected {
                self.connectionState = .reconnecting(attempt: Int(delay))
                await self.doConnect()
            }
        }
    }

    private func deriveSessionKey(withPeerPublicKey peerKey: String) throws {
        let peerData = try Base64URL.decode(peerKey)
        let peerPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerData)
        let shared = try keyPair.privateKey.sharedSecretFromKeyAgreement(with: peerPub)

        let salt = SHA256.hash(data: Data("conduit-relay-salt".utf8))
        sessionKey = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(salt),
            sharedInfo: Data("conduit-relay-v1".utf8),
            outputByteCount: 32
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

struct E2EInnerMessageDecoded: Codable {
    let type: String
    let payload: Data
}

// MARK: - Errors

public enum E2EError: Error, LocalizedError {
    case notConnected
    case notPaired
    case encryptFailed
    case decryptFailed

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to relay"
        case .notPaired: return "Not paired with daemon"
        case .encryptFailed: return "Encryption failed"
        case .decryptFailed: return "Decryption failed"
        }
    }
}
