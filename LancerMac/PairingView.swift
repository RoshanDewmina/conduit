import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins
import DesignSystem
import HostControlKit

/// Phone-pairing screen: requests a one-time pairing session from `lancerd`
/// and renders it as a scannable QR code plus a manually-typeable 6-digit
/// code. Mirrors the iOS app's `BridgePairingView` wire contract
/// (`agent.pair.begin` → `PairingPayload`) but on the macOS side of the pair.
struct PairingView: View {
    @Environment(HostModel.self) private var host
    @Environment(\.lancerTokens) private var tokens

    @State private var payload: PairingPayload?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: tokens.s7) {
            switch (payload, errorMessage) {
            case (let payload?, _):
                successContent(payload)
            case (nil, let message?):
                failureContent(message)
            default:
                loadingContent
            }
        }
        .padding(tokens.s8)
        .frame(minWidth: 360, minHeight: 420)
        .task {
            await beginPairing()
        }
    }

    // MARK: - States

    private var loadingContent: some View {
        VStack(spacing: tokens.s5) {
            ProgressView()
            Text("Starting pairing session…")
                .font(.dsSansPt(13))
                .foregroundStyle(tokens.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureContent(_ message: String) -> some View {
        VStack(spacing: tokens.s5) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(tokens.danger)
            Text("Couldn't start pairing")
                .font(.dsDisplayPt(16))
                .foregroundStyle(tokens.text)
            Text(message)
                .font(.dsSansPt(13))
                .foregroundStyle(tokens.text2)
                .multilineTextAlignment(.center)
            DSButton("Retry", systemImage: "arrow.clockwise", variant: .primary) {
                Task { await beginPairing() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func successContent(_ payload: PairingPayload) -> some View {
        VStack(spacing: tokens.s6) {
            Text("Pair a device")
                .font(.dsDisplayPt(20))
                .foregroundStyle(tokens.text)

            if let qrImage = Self.qrImage(from: payload.qrPayload) {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                    .padding(tokens.s5)
                    .background(tokens.surface)
                    .clipShape(RoundedRectangle(cornerRadius: tokens.r4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: tokens.r4, style: .continuous)
                            .strokeBorder(tokens.border, lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: tokens.r4, style: .continuous)
                    .fill(tokens.surfaceSunk)
                    .frame(width: 220, height: 220)
                    .overlay(
                        Text("QR unavailable")
                            .font(.dsSansPt(12))
                            .foregroundStyle(tokens.text3)
                    )
            }

            VStack(spacing: tokens.s3) {
                Text(formattedCode(payload.code))
                    .font(.dsMonoPt(28, weight: .medium))
                    .foregroundStyle(tokens.text)
                    .tracking(2)

                DSButton("Copy code", systemImage: "doc.on.doc", variant: .secondary, size: .sm) {
                    copyToClipboard(payload.code)
                }
            }

            Text("Scan with the Lancer iPhone app, or enter the code manually.")
                .font(.dsSansPt(12))
                .foregroundStyle(tokens.text3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func beginPairing() async {
        isLoading = true
        errorMessage = nil
        do {
            payload = try await host.beginPairing()
        } catch let error as HostServiceError {
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func copyToClipboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func formattedCode(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let mid = code.index(code.startIndex, offsetBy: 3)
        return "\(code[code.startIndex..<mid]) \(code[mid...])"
    }

    private static func message(for error: HostServiceError) -> String {
        switch error {
        case .notConnected:
            return "Host Service not running"
        case .rpc(let code, let message):
            return "RPC error \(code): \(message)"
        case .decoding:
            return "Malformed response from Host Service"
        case .socket(let detail):
            return detail
        case .versionMismatch:
            return "Host Service version mismatch"
        }
    }

    /// Renders `string` as a QR code `NSImage`. Uses CoreImage's
    /// `qrCodeGenerator` at "M" error correction, then scales the bitmap up
    /// with an affine transform (nearest-neighbor — the source is already a
    /// hard-edged module grid) for a crisp on-screen result.
    private static func qrImage(from string: String) -> NSImage? {
        guard let data = string.data(using: .utf8) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}
