import SwiftUI
import LancerCore

#if os(iOS)
import UIKit

/// Adaptive strip of sent attachment thumbnails / file cards above a user prompt.
struct ChatAttachmentStrip: View {
    let attachments: [ConversationAttachmentReference]
    var previewCache: AttachmentPreviewCaching
    var mediaStore: AttachmentLocalMediaCaching
    @State private var fullScreen: ConversationAttachmentReference?

    init(
        attachments: [ConversationAttachmentReference],
        previewCache: AttachmentPreviewCaching? = nil,
        mediaStore: AttachmentLocalMediaCaching? = nil
    ) {
        self.attachments = attachments
        if let previewCache {
            self.previewCache = previewCache
        } else if let cache = try? AttachmentPreviewCache() {
            self.previewCache = cache
        } else {
            self.previewCache = NullAttachmentPreviewCache()
        }
        if let mediaStore {
            self.mediaStore = mediaStore
        } else if let store = try? AttachmentLocalMediaStore() {
            self.mediaStore = store
        } else {
            self.mediaStore = NullAttachmentLocalMediaStore()
        }
    }

    private var mediaAttachments: [ConversationAttachmentReference] {
        attachments.filter {
            AttachmentMediaClassification.classify(reference: $0).isInlineMedia
        }
    }

    private var fileAttachments: [ConversationAttachmentReference] {
        attachments.filter {
            !AttachmentMediaClassification.classify(reference: $0).isInlineMedia
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !mediaAttachments.isEmpty {
                mediaRow(mediaAttachments)
            }
            ForEach(fileAttachments) { file in
                ChatAttachmentFileCard(reference: file, previewCache: previewCache)
            }
        }
        .fullScreenCover(item: $fullScreen) { ref in
            AttachmentMediaFullScreen(
                reference: ref,
                previewCache: previewCache,
                mediaStore: mediaStore
            ) {
                fullScreen = nil
            }
        }
    }

    @ViewBuilder
    private func mediaRow(_ media: [ConversationAttachmentReference]) -> some View {
        if media.count == 1, let only = media.first {
            AttachmentMediaView(
                reference: only,
                previewCache: previewCache,
                mediaStore: mediaStore,
                maxHeight: 220
            ) {
                fullScreen = only
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(media) { item in
                        AttachmentMediaView(
                            reference: item,
                            previewCache: previewCache,
                            mediaStore: mediaStore,
                            maxHeight: 220
                        ) {
                            fullScreen = item
                        }
                        .frame(width: 160)
                    }
                }
            }
        }
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

    private var mediaKind: AttachmentMediaClassification {
        AttachmentMediaClassification.classify(reference: reference)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: fileIconName)
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

    private var fileIconName: String {
        switch mediaKind {
        case .image: return "photo"
        case .video: return "video"
        case .file: return "doc.fill"
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
