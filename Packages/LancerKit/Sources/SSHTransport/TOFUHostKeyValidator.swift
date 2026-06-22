import Foundation
import CryptoKit
@preconcurrency import NIOCore
@preconcurrency import NIOSSH
import LancerCore
import SecurityKit

/// Trust-on-first-use host key validation for Citadel/NIOSSH.
///
/// Unknown fingerprint → fails with `LancerError.hostKeyUnknown` so the UI
/// can show a confirmation sheet. After the user trusts and `HostKeyStore.record`
/// is called, a retry connect will hit the `.match` branch and succeed.
final class TOFUHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let hostID: HostID
    private let store: HostKeyStore

    init(hostID: HostID, store: HostKeyStore) {
        self.hostID = hostID
        self.store = store
    }

    func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        let fingerprint = Self.fingerprint(of: hostKey)

        Task {
            switch await store.verify(hostID: hostID, presented: fingerprint) {
            case .match:
                validationCompletePromise.succeed(())
            case .unknown:
                validationCompletePromise.fail(LancerError.hostKeyUnknown(fingerprint: fingerprint))
            case .mismatch(let expected, let actual):
                validationCompletePromise.fail(
                    LancerError.hostKeyMismatch(expected: expected, actual: actual)
                )
            }
        }
    }

    static func fingerprint(of key: NIOSSHPublicKey) -> String {
        var buffer = ByteBufferAllocator().buffer(capacity: 256)
        key.write(to: &buffer)
        let digest = SHA256.hash(data: buffer.readableBytesView)
        let base64 = Data(digest).base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return "SHA256:\(base64)"
    }
}
