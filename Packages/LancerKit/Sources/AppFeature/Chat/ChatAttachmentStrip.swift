import SwiftUI
import LancerCore

#if os(iOS)
import UIKit

/// Adaptive strip of sent attachment thumbnails / file cards above a user prompt.
struct ChatAttachmentStrip: View {
    let attachments: [ConversationAttachmentReference]
    var previewCache: AttachmentPreviewCaching
    @State private var fullScreen: ConversationAttachmentReference?

    init(
        attachments: [ConversationAttachmentReference],
        previewCache: AttachmentPreviewCaching? = nil
    ) {
        self.attachments = attachments
        if let previewCache {
            self.previewCache = previewCache
        } else if let cache = try? AttachmentPreviewCache() {
            self.previewCache = cache
        } else {
            self.previewCache = NullAttachmentPreviewCache()
        }
    }

    var body: some View {
        let images = attachments.filter { $0.kind == .image }
        let files = attachments.filter { $0.kind != .image }
        VStack(alignment: .leading, spacing: 8) {
            if !images.isEmpty {
                imageGrid(images)
            }
            ForEach(files) { file in
                ChatAttachmentFileCard(reference: file, previewCache: previewCache)
            }
        }
        .fullScreenCover(item: $fullScreen) { ref in
            AttachmentFullScreenPreview(reference: ref, previewCache: previewCache) {
                fullScreen = nil
            }
        }
    }

    @ViewBuilder
    private func imageGrid(_ images: [ConversationAttachmentReference]) -> some View {
        let columns = AttachmentLayoutPolicy.columns(for: images.count)
        if columns <= 1, let only = images.first {
            AttachmentPreviewView(reference: only, previewCache: previewCache, prominent: true) {
                fullScreen = only
            }
        } else {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: max(columns, 1)),
                spacing: 8
            ) {
                ForEach(images) { image in
                    AttachmentPreviewView(reference: image, previewCache: previewCache, prominent: false) {
                        fullScreen = image
                    }
                }
            }
        }
    }
}

struct AttachmentPreviewView: View {
    let reference: ConversationAttachmentReference
    var previewCache: AttachmentPreviewCaching
    var prominent: Bool
    var onTap: () -> Void

    @State private var image: UIImage?
    @State private var loadFailed = false

    private var presentation: AttachmentPresentation {
        AttachmentPresentation.card(for: reference, previewAvailable: image != nil && !loadFailed)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                    VStack(spacing: 6) {
                        Image(systemName: loadFailed ? "photo.badge.exclamationmark" : "photo")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(reference.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(10)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: prominent ? 220 : 120)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(presentation.accessibilityLabel))
        .task(id: reference.previewCacheKey) {
            await loadPreview()
        }
    }

    private func loadPreview() async {
        loadFailed = false
        image = nil
        let key = reference.previewCacheKey
        let data = try? previewCache.previewData(for: key)
        guard !Task.isCancelled else { return }
        guard let data, let decoded = UIImage(data: data) else {
            loadFailed = true
            return
        }
        image = decoded
    }
}

struct ChatAttachmentFileCard: View {
    let reference: ConversationAttachmentReference
    var previewCache: AttachmentPreviewCaching
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var nameSize: CGFloat = 15

    private var presentation: AttachmentPresentation {
        AttachmentPresentation.card(for: reference, previewAvailable: false)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reference.kind == .image ? "photo" : "doc.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.displayName)
                    .font(.system(size: nameSize, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(presentation.sizeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemFill))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(presentation.accessibilityLabel))
        // V1: file cards are not tappable / Quick Look — never open hostPath.
    }
}

struct AttachmentFullScreenPreview: View {
    let reference: ConversationAttachmentReference
    var previewCache: AttachmentPreviewCaching
    var onClose: () -> Void
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                } else {
                    ChatAttachmentFileCard(reference: reference, previewCache: previewCache)
                        .padding()
                }
            }
            .navigationTitle(reference.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
        .task(id: reference.previewCacheKey) {
            if let data = try? previewCache.previewData(for: reference.previewCacheKey) {
                image = UIImage(data: data)
            }
        }
    }
}

/// Fallback cache when Application Support cannot be created in tests/previews.
struct NullAttachmentPreviewCache: AttachmentPreviewCaching {
    func storePreview(_ data: Data, for key: String) throws {}
    func previewData(for key: String) throws -> Data? { nil }
    func removePreview(for key: String) throws {}
}
#endif
