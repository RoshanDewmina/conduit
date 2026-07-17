import Foundation
import LancerCore

#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(ImageIO)
import ImageIO
import CoreGraphics
#endif

/// Phone-side original media bytes for locally-sent attachments (videos today).
/// Keys match `ConversationAttachmentReference.previewCacheKey` — never host paths.
/// There is no `attachment.get` RPC; mirrored/other-device refs will miss here.
public protocol AttachmentLocalMediaCaching: Sendable {
    func storeMedia(_ data: Data, for key: String, fileExtension: String) throws
    func mediaFileURL(for key: String) throws -> URL?
    func removeMedia(for key: String) throws
}

/// Bounded original-media store under Application Support (videos for AVPlayer).
public final class AttachmentLocalMediaStore: AttachmentLocalMediaCaching, @unchecked Sendable {
    public static let defaultMaxEntries = 40
    public static let defaultMaxTotalBytes = 200 * 1024 * 1024
    public static let defaultMaxBytesPerEntry = AttachmentLimits.maxBytesPerFile

    private let directory: URL
    private let maxEntries: Int
    private let maxTotalBytes: Int
    private let maxBytesPerEntry: Int
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(
        directory: URL? = nil,
        maxEntries: Int = AttachmentLocalMediaStore.defaultMaxEntries,
        maxTotalBytes: Int = AttachmentLocalMediaStore.defaultMaxTotalBytes,
        maxBytesPerEntry: Int = AttachmentLocalMediaStore.defaultMaxBytesPerEntry,
        fileManager: FileManager = .default
    ) throws {
        self.fileManager = fileManager
        self.maxEntries = max(1, maxEntries)
        self.maxTotalBytes = max(1, maxTotalBytes)
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
            self.directory = root.appendingPathComponent("Lancer/AttachmentMedia", isDirectory: true)
        }
        try fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public func storeMedia(_ data: Data, for key: String, fileExtension: String) throws {
        let sanitized = try AttachmentPreviewCache.sanitizeKey(key)
        guard !data.isEmpty else { return }
        guard data.count <= maxBytesPerEntry else {
            throw AttachmentPreviewCacheError.entryTooLarge
        }
        let ext = Self.normalizedExtension(fileExtension)
        lock.lock()
        defer { lock.unlock() }
        // Drop any prior extension variants for this key.
        for existing in siblingURLsUnlocked(for: sanitized) {
            try? fileManager.removeItem(at: existing)
        }
        let url = fileURLUnlocked(for: sanitized, ext: ext)
        let temp = directory.appendingPathComponent(".\(sanitized).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temp, options: .atomic)
            try fileManager.moveItem(at: temp, to: url)
        } catch {
            try? fileManager.removeItem(at: temp)
            throw AttachmentPreviewCacheError.ioFailure
        }
        try enforceCapsUnlocked()
    }

    public func mediaFileURL(for key: String) throws -> URL? {
        let sanitized = try AttachmentPreviewCache.sanitizeKey(key)
        lock.lock()
        defer { lock.unlock() }
        return siblingURLsUnlocked(for: sanitized).first
    }

    public func removeMedia(for key: String) throws {
        let sanitized = try AttachmentPreviewCache.sanitizeKey(key)
        lock.lock()
        defer { lock.unlock() }
        for url in siblingURLsUnlocked(for: sanitized) {
            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: - Persist after send

    /// Writes image previews + video originals from drafts that just uploaded.
    /// Call before clearing composer drafts. Silent on failure (UI falls back to file chip).
    public static func persistSentDrafts(
        _ drafts: [AttachmentDraft],
        previewCache: AttachmentPreviewCaching?,
        mediaStore: AttachmentLocalMediaCaching? = nil
    ) async {
        let store: AttachmentLocalMediaCaching?
        if let mediaStore {
            store = mediaStore
        } else {
            store = try? AttachmentLocalMediaStore()
        }
        for draft in drafts {
            guard case .done = draft.state else { continue }
            let media = AttachmentMediaClassification.classify(
                mimeType: draft.mimeType, fileName: draft.name
            )
            let key = draft.id.uuidString
            switch media {
            case .image:
                if let preview = await AttachmentPreviewCache.makePreviewDataOffMain(
                    from: draft.data, mimeType: draft.mimeType
                ) {
                    try? previewCache?.storePreview(preview, for: key)
                }
            case .video:
                let ext = (draft.name as NSString).pathExtension
                try? store?.storeMedia(draft.data, for: key, fileExtension: ext.isEmpty ? "mp4" : ext)
                if let thumb = await makeVideoThumbnailData(from: draft.data, fileExtension: ext),
                   let previewCache {
                    try? previewCache.storePreview(thumb, for: key)
                }
            case .file:
                break
            }
        }
    }

    /// Best-effort first-frame JPEG for a video draft (nil off-Apple / on failure).
    public static func makeVideoThumbnailData(
        from data: Data,
        fileExtension: String
    ) async -> Data? {
        #if canImport(AVFoundation)
        let ext = normalizedExtension(fileExtension.isEmpty ? "mp4" : fileExtension)
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lancer-vid-\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: temp, options: .atomic)
            defer { try? FileManager.default.removeItem(at: temp) }
            return await jpegThumbnail(for: temp)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    #if canImport(AVFoundation)
    private static func jpegThumbnail(for url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(
            width: AttachmentPreviewCache.maxPreviewPixelDimension,
            height: AttachmentPreviewCache.maxPreviewPixelDimension
        )
        let time = CMTime(seconds: 0.05, preferredTimescale: 600)
        let cgImage: CGImage? = await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, _ in
                continuation.resume(returning: image)
            }
        }
        guard let cgImage else { return nil }
        let mutable = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutable, "public.jpeg" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination, cgImage,
            [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        let out = mutable as Data
        guard out.count <= AttachmentPreviewCache.defaultMaxOutputBytes else { return nil }
        return out
    }
    #endif

    // MARK: - Internals

    private func fileURLUnlocked(for sanitizedKey: String, ext: String) -> URL {
        directory.appendingPathComponent("\(sanitizedKey).\(ext)", isDirectory: false)
    }

    private func siblingURLsUnlocked(for sanitizedKey: String) -> [URL] {
        let prefix = sanitizedKey + "."
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix(prefix) }
    }

    private func enforceCapsUnlocked() throws {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var entries: [(url: URL, size: Int, modified: Date)] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values?.fileSize ?? 0
            let modified = values?.contentModificationDate ?? .distantPast
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

    static func normalizedExtension(_ raw: String) -> String {
        let trimmed = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let allowed = CharacterSet.alphanumerics
        let filtered = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
        return filtered.isEmpty ? "bin" : String(filtered.prefix(8))
    }
}

/// Test / preview stand-in that never persists.
public struct NullAttachmentLocalMediaStore: AttachmentLocalMediaCaching {
    public init() {}
    public func storeMedia(_ data: Data, for key: String, fileExtension: String) throws {}
    public func mediaFileURL(for key: String) throws -> URL? { nil }
    public func removeMedia(for key: String) throws {}
}
