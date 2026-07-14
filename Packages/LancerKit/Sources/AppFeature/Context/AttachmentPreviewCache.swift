import Foundation
import LancerCore

#if canImport(ImageIO)
import ImageIO
#endif

/// Phone-side preview bytes for sent attachments. Keys are `previewCacheKey`
/// values from `ConversationAttachmentReference` — never host paths.
public protocol AttachmentPreviewCaching: Sendable {
    func storePreview(_ data: Data, for key: String) throws
    func previewData(for key: String) throws -> Data?
    func removePreview(for key: String) throws
}

public enum AttachmentPreviewCacheError: Error, Equatable, Sendable {
    case invalidKey
    case ioFailure
    case entryTooLarge
    case inputTooLarge
}

/// Bounded on-device preview store under Application Support / a test directory.
///
/// Scope: when `accountScope` is provided the root is
/// `…/Lancer/AttachmentPreviews/<accountScope>/`; otherwise a single-user
/// default root is used (documented single-user / local-device scope until
/// multi-account identity is threaded into the composer).
/// Foundation-only I/O so package tests can exercise it without UIKit.
public final class AttachmentPreviewCache: AttachmentPreviewCaching, @unchecked Sendable {
    public static let defaultMaxEntries = 200
    public static let defaultMaxTotalBytes = 64 * 1024 * 1024
    public static let defaultMaxAge: TimeInterval = 30 * 24 * 3600
    public static let maxPreviewPixelDimension = 1024
    /// Reject store/write above this size (post-downsample preview bytes).
    public static let defaultMaxBytesPerEntry = 2 * 1024 * 1024
    /// Reject ImageIO input above this size before decode.
    public static let defaultMaxInputBytes = 25 * 1024 * 1024
    /// Cap JPEG output from downsample.
    public static let defaultMaxOutputBytes = 2 * 1024 * 1024

    private let directory: URL
    private let maxEntries: Int
    private let maxTotalBytes: Int
    private let maxAge: TimeInterval
    private let maxBytesPerEntry: Int
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(
        directory: URL? = nil,
        accountScope: String? = nil,
        maxEntries: Int = AttachmentPreviewCache.defaultMaxEntries,
        maxTotalBytes: Int = AttachmentPreviewCache.defaultMaxTotalBytes,
        maxAge: TimeInterval = AttachmentPreviewCache.defaultMaxAge,
        maxBytesPerEntry: Int = AttachmentPreviewCache.defaultMaxBytesPerEntry,
        fileManager: FileManager = .default
    ) throws {
        self.fileManager = fileManager
        self.maxEntries = max(1, maxEntries)
        self.maxTotalBytes = max(1, maxTotalBytes)
        self.maxAge = max(0, maxAge)
        self.maxBytesPerEntry = max(1, maxBytesPerEntry)
        if let directory {
            self.directory = directory
        } else {
            let root = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            var path = root.appendingPathComponent("Lancer/AttachmentPreviews", isDirectory: true)
            if let accountScope, !accountScope.isEmpty {
                let sanitized = try Self.sanitizeKey(accountScope)
                path = path.appendingPathComponent(sanitized, isDirectory: true)
            }
            self.directory = path
        }
        try fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
        try Self.applyCacheDirectoryProtection(at: self.directory, fileManager: fileManager)
    }

    public func storePreview(_ data: Data, for key: String) throws {
        let sanitized = try Self.sanitizeKey(key)
        guard !data.isEmpty else { return }
        guard data.count <= maxBytesPerEntry else {
            throw AttachmentPreviewCacheError.entryTooLarge
        }
        lock.lock()
        defer { lock.unlock() }
        let url = fileURLUnlocked(for: sanitized)
        // Reject path escape / symlink collision on the destination leaf.
        if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
           let type = attrs[.type] as? FileAttributeType,
           type == .typeSymbolicLink {
            try? fileManager.removeItem(at: url)
        }
        let resolvedDir = directory.resolvingSymlinksInPath()
        guard url.path.hasPrefix(resolvedDir.path + "/") || url.deletingLastPathComponent() == resolvedDir else {
            throw AttachmentPreviewCacheError.invalidKey
        }
        let temp = directory.appendingPathComponent(".\(sanitized).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temp, options: .atomic)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.moveItem(at: temp, to: url)
            try Self.applyFileProtection(at: url, fileManager: fileManager)
        } catch let error as AttachmentPreviewCacheError {
            try? fileManager.removeItem(at: temp)
            throw error
        } catch {
            try? fileManager.removeItem(at: temp)
            throw AttachmentPreviewCacheError.ioFailure
        }
        try enforceCapsUnlocked()
    }

    public func previewData(for key: String) throws -> Data? {
        let sanitized = try Self.sanitizeKey(key)
        lock.lock()
        defer { lock.unlock() }
        let url = fileURLUnlocked(for: sanitized)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        if isExpired(url) {
            try? fileManager.removeItem(at: url)
            return nil
        }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return data
    }

    public func removePreview(for key: String) throws {
        let sanitized = try Self.sanitizeKey(key)
        lock.lock()
        defer { lock.unlock() }
        let url = fileURLUnlocked(for: sanitized)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Resolved file URL for a sanitized key — used by tests to inject corrupt files.
    public func fileURL(for key: String) throws -> URL {
        let sanitized = try Self.sanitizeKey(key)
        lock.lock()
        defer { lock.unlock() }
        return fileURLUnlocked(for: sanitized)
    }

    /// Downsamples image bytes for preview storage. Returns nil for non-images
    /// or decode failures — callers fall back to a file card.
    public static func makePreviewData(
        from original: Data,
        mimeType: String?,
        maxPixelDimension: Int = AttachmentPreviewCache.maxPreviewPixelDimension,
        maxInputBytes: Int = AttachmentPreviewCache.defaultMaxInputBytes,
        maxOutputBytes: Int = AttachmentPreviewCache.defaultMaxOutputBytes
    ) -> Data? {
        guard original.count <= maxInputBytes else { return nil }
        let isImage = mimeType?.hasPrefix("image/") == true
            || (mimeType == nil && looksLikeImage(original))
        guard isImage else { return nil }
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(original as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixelDimension),
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let mutable = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutable, "public.jpeg" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        let data = mutable as Data
        guard data.count <= maxOutputBytes else { return nil }
        return data
        #else
        // Non-Apple platforms used by package tests: keep a small bounded copy.
        let cap = min(64 * 1024, maxOutputBytes)
        return original.count <= cap ? original : Data(original.prefix(cap))
        #endif
    }

    /// Cancellation-aware ImageIO downsample off the cooperative main actor.
    public static func makePreviewDataOffMain(
        from original: Data,
        mimeType: String?,
        maxPixelDimension: Int = AttachmentPreviewCache.maxPreviewPixelDimension
    ) async -> Data? {
        if Task.isCancelled { return nil }
        guard original.count <= defaultMaxInputBytes else { return nil }
        return await Task.detached(priority: .userInitiated) {
            if Task.isCancelled { return nil }
            return makePreviewData(
                from: original,
                mimeType: mimeType,
                maxPixelDimension: maxPixelDimension
            )
        }.value
    }

    // MARK: - Internals

    private func fileURLUnlocked(for sanitizedKey: String) -> URL {
        directory.appendingPathComponent("\(sanitizedKey).preview", isDirectory: false)
    }

    private func isExpired(_ url: URL) -> Bool {
        guard maxAge > 0,
              let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let modified = values.contentModificationDate
        else { return false }
        return Date().timeIntervalSince(modified) > maxAge
    }

    private func enforceCapsUnlocked() throws {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var entries: [(url: URL, size: Int, modified: Date)] = []
        for url in urls where url.pathExtension == "preview" {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values?.fileSize ?? 0
            let modified = values?.contentModificationDate ?? .distantPast
            if maxAge > 0, Date().timeIntervalSince(modified) > maxAge {
                try? fileManager.removeItem(at: url)
                continue
            }
            if size <= 0 {
                try? fileManager.removeItem(at: url)
                continue
            }
            if size > maxBytesPerEntry {
                try? fileManager.removeItem(at: url)
                continue
            }
            entries.append((url, size, modified))
        }
        entries.sort { $0.modified < $1.modified }
        var total = entries.reduce(0) { $0 + $1.size }
        while entries.count > maxEntries || total > maxTotalBytes {
            guard let oldest = entries.first else { break }
            try? fileManager.removeItem(at: oldest.url)
            total -= oldest.size
            entries.removeFirst()
        }
    }

    static func sanitizeKey(_ key: String) throws -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AttachmentPreviewCacheError.invalidKey }
        if trimmed.contains("/") || trimmed.contains("\\") || trimmed.contains("..") {
            throw AttachmentPreviewCacheError.invalidKey
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw AttachmentPreviewCacheError.invalidKey
        }
        return trimmed
    }

    private static func looksLikeImage(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let jpeg = data.starts(with: [0xFF, 0xD8, 0xFF])
        let png = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
        let gif = data.starts(with: Array("GIF8".utf8))
        return jpeg || png || gif
    }

    private static func applyCacheDirectoryProtection(at url: URL, fileManager: FileManager) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try? mutable.setResourceValues(values)
        try applyFileProtection(at: url, fileManager: fileManager)
    }

    private static func applyFileProtection(at url: URL, fileManager: FileManager) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try? mutable.setResourceValues(values)
        #if os(iOS) || os(visionOS) || os(tvOS) || os(watchOS)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}
