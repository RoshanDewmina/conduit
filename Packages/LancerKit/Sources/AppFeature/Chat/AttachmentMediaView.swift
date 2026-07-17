/*
 Scout findings (CC-10, 2026-07-16) — attachment byte flow on phone:

 1. Composer / ContextAttachView builds AttachmentDraft with in-memory `data` + mime.
 2. On send, AttachmentUploader chunks bytes via attachment.put (relay or SSH).
 3. ConversationAttachmentReference is persisted (local SQLite + daemon attachments_json)
    with previewCacheKey = draft UUID. hostPath is daemon-side only — never opened on phone.
 4. Image preview bytes: AttachmentPreviewCache under Application Support, written at send
    from draft.data via makePreviewData. ChatAttachmentStrip loads by previewCacheKey.
 5. There is NO attachment.get / download RPC for mirrored or other-device attachments.
    Mirrored refs only carry metadata; without a local cache hit they cannot render pixels.
 6. Videos were classified as wire kind `.file` and rendered as ChatAttachmentFileCard.
    This file adds inline image/video UI for locally-sent media (cache hit). Mirrored
    media without local bytes falls back to the file chip — not faked.
 */
import SwiftUI
import LancerCore

#if os(iOS)
import UIKit
import AVKit

/// Inline image / video thumbnail for a user bubble. Tap → full-screen viewer.
struct AttachmentMediaView: View {
    let reference: ConversationAttachmentReference
    var previewCache: AttachmentPreviewCaching
    var mediaStore: AttachmentLocalMediaCaching
    var maxHeight: CGFloat = 220
    var onTap: () -> Void

    @State private var image: UIImage?
    @State private var loadState: LoadState = .loading

    private enum LoadState {
        case loading
        case ready
        case failed
    }

    private var mediaKind: AttachmentMediaClassification {
        AttachmentMediaClassification.classify(reference: reference)
    }

    var body: some View {
        Group {
            switch loadState {
            case .failed:
                ChatAttachmentFileCard(reference: reference, previewCache: previewCache)
            case .loading, .ready:
                Button(action: onTap) {
                    ZStack {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .frame(maxHeight: maxHeight)
                        } else {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.tertiarySystemFill))
                                .frame(maxWidth: .infinity)
                                .frame(height: maxHeight)
                            ProgressView()
                                .controlSize(.regular)
                                .tint(.secondary)
                        }
                        if mediaKind == .video, loadState == .ready {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 44))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.45))
                                .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                                .allowsHitTesting(false)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(.separator), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(accessibilityLabel))
            }
        }
        .task(id: reference.previewCacheKey) {
            await loadPreview()
        }
    }

    private var accessibilityLabel: String {
        let base = AttachmentPresentation.card(
            for: reference, previewAvailable: image != nil
        ).accessibilityLabel
        if mediaKind == .video {
            return "Video, \(base)"
        }
        return base
    }

    private func loadPreview() async {
        loadState = .loading
        image = nil
        let key = reference.previewCacheKey
        let data = try? previewCache.previewData(for: key)
        guard !Task.isCancelled else { return }
        if let data, let decoded = UIImage(data: data) {
            image = decoded
            loadState = .ready
            return
        }
        // Video without a stored frame still opens if original bytes are local.
        if mediaKind == .video,
           let _ = try? mediaStore.mediaFileURL(for: key) {
            loadState = .ready
            return
        }
        loadState = .failed
    }
}

/// Full-screen image (optional pinch) or AVPlayer for locally-cached video.
struct AttachmentMediaFullScreen: View {
    let reference: ConversationAttachmentReference
    var previewCache: AttachmentPreviewCaching
    var mediaStore: AttachmentLocalMediaCaching
    var onClose: () -> Void

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var zoom: CGFloat = 1

    private var mediaKind: AttachmentMediaClassification {
        AttachmentMediaClassification.classify(reference: reference)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle(reference.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task(id: reference.previewCacheKey) {
            await load()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mediaKind {
        case .video:
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                fallbackCard
            }
        case .image, .file:
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoom)
                    .gesture(
                        MagnificationGesture().onChanged { value in
                            zoom = max(1, min(value, 4))
                        }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            zoom = zoom > 1 ? 1 : 2
                        }
                    }
                    .padding()
            } else {
                fallbackCard
            }
        }
    }

    private var fallbackCard: some View {
        ChatAttachmentFileCard(reference: reference, previewCache: previewCache)
            .padding()
    }

    private func load() async {
        let key = reference.previewCacheKey
        if mediaKind == .video {
            if let url = try? mediaStore.mediaFileURL(for: key) {
                let av = AVPlayer(url: url)
                player = av
                av.play()
                return
            }
        }
        if let data = try? previewCache.previewData(for: key) {
            image = UIImage(data: data)
        }
    }
}
#endif
