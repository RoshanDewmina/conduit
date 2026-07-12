#if os(iOS)
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Context attach sheet — Photos / Screenshots / Camera / Files pickers feed
/// `attachments` (chips also mirror into the composer). MCP Servers removed.
public struct ContextAttachView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var attachments: [AttachmentDraft]
    @State private var selectedMode: ContextMode = .plan
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var screenshotItems: [PhotosPickerItem] = []
    @State private var isPhotosPresented = false
    @State private var isScreenshotsPresented = false
    @State private var isCameraPresented = false
    @State private var isFilesPresented = false
    @State private var loadError: String?

    public init(attachments: Binding<[AttachmentDraft]>) {
        _attachments = attachments
    }

    /// Preview / DEBUG destinations that don't own composer drafts yet.
    public init() {
        _attachments = .constant([])
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RepoSheetHeader(title: "Context") { dismiss() }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 16)

                recentStrip
                    .padding(.bottom, 24)

                RepoSectionHeader(title: "Mode")

                VStack(spacing: 0) {
                    ForEach(ContextMode.allCases) { mode in
                        ContextModeRow(mode: mode, isSelected: selectedMode == mode) {
                            selectedMode = mode
                        }
                        Divider()
                            .padding(.leading, 58)
                    }
                }
                .padding(.top, 20)

                RepoSectionHeader(title: "Add")
                    .padding(.top, 24)

                VStack(spacing: 0) {
                    ContextAddRow(row: .photos) { isPhotosPresented = true }
                    Divider().padding(.leading, 58)
                    ContextAddRow(row: .screenshots) { isScreenshotsPresented = true }
                    Divider().padding(.leading, 58)
                    ContextAddRow(row: .camera) { isCameraPresented = true }
                    Divider().padding(.leading, 58)
                    ContextAddRow(row: .files) { isFilesPresented = true }
                }
                .padding(.top, 20)

                if let loadError {
                    Text(loadError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .photosPicker(
            isPresented: $isPhotosPresented,
            selection: $photoItems,
            maxSelectionCount: remainingSlots,
            matching: .images
        )
        .photosPicker(
            isPresented: $isScreenshotsPresented,
            selection: $screenshotItems,
            maxSelectionCount: remainingSlots,
            matching: .screenshots
        )
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraImagePicker { image in
                ingestCameraImage(image)
            }
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $isFilesPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            Task { await ingestFiles(result) }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await ingestPhotos(items, defaultName: "photo")
                photoItems = []
            }
        }
        .onChange(of: screenshotItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await ingestPhotos(items, defaultName: "screenshot")
                screenshotItems = []
            }
        }
    }

    private var remainingSlots: Int {
        max(0, AttachmentLimits.maxFiles - attachments.count)
    }

    @ViewBuilder
    private var recentStrip: some View {
        if attachments.isEmpty {
            Text("No recent context yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { draft in
                        AttachmentChipView(draft: draft) {
                            attachments.removeAll { $0.id == draft.id }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func ingestCameraImage(_ image: UIImage) {
        guard remainingSlots > 0 else {
            loadError = "At most \(AttachmentLimits.maxFiles) files"
            return
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            loadError = "Couldn't read that photo"
            return
        }
        guard data.count <= AttachmentLimits.maxBytesPerFile else {
            loadError = "Each file must be ≤ 20 MB"
            return
        }
        let name = "camera-\(Int(Date().timeIntervalSince1970)).jpg"
        attachments = AttachmentDraftStore.appending(
            attachments,
            newItems: [AttachmentDraft(name: name, data: data)]
        )
        loadError = nil
    }

    private func ingestPhotos(_ items: [PhotosPickerItem], defaultName: String) async {
        var added: [AttachmentDraft] = []
        var sawLoadFailure = false
        for (index, item) in items.enumerated() {
            guard attachments.count + added.count < AttachmentLimits.maxFiles else { break }
            let data: Data
            do {
                guard let loaded = try await item.loadTransferable(type: Data.self), !loaded.isEmpty else {
                    sawLoadFailure = true
                    continue
                }
                data = loaded
            } catch {
                sawLoadFailure = true
                continue
            }
            guard data.count <= AttachmentLimits.maxBytesPerFile else {
                await MainActor.run { loadError = "Each file must be ≤ 20 MB" }
                continue
            }
            let ext = suggestedExtension(for: item) ?? "jpg"
            let name = "\(defaultName)-\(index + 1).\(ext)"
            added.append(AttachmentDraft(name: name, data: data))
        }
        await MainActor.run {
            attachments = AttachmentDraftStore.appending(attachments, newItems: added)
            if !added.isEmpty {
                loadError = nil
            } else if sawLoadFailure {
                loadError = "Couldn't load that photo"
            }
        }
    }

    private func ingestFiles(_ result: Result<[URL], Error>) async {
        switch result {
        case .failure(let error):
            await MainActor.run { loadError = error.localizedDescription }
        case .success(let urls):
            var added: [AttachmentDraft] = []
            var sawLoadFailure = false
            for url in urls {
                guard attachments.count + added.count < AttachmentLimits.maxFiles else { break }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let data: Data
                do {
                    data = try Data(contentsOf: url)
                    guard !data.isEmpty else {
                        sawLoadFailure = true
                        continue
                    }
                } catch {
                    sawLoadFailure = true
                    continue
                }
                guard data.count <= AttachmentLimits.maxBytesPerFile else {
                    await MainActor.run { loadError = "Each file must be ≤ 20 MB" }
                    continue
                }
                added.append(AttachmentDraft(name: url.lastPathComponent, data: data))
            }
            await MainActor.run {
                attachments = AttachmentDraftStore.appending(attachments, newItems: added)
                if !added.isEmpty {
                    loadError = nil
                } else if sawLoadFailure {
                    loadError = "Couldn't load that file"
                }
            }
        }
    }

    private func suggestedExtension(for item: PhotosPickerItem) -> String? {
        guard let type = item.supportedContentTypes.first else { return nil }
        if type.conforms(to: .png) { return "png" }
        if type.conforms(to: .jpeg) { return "jpg" }
        if type.conforms(to: .heic) { return "heic" }
        if type.conforms(to: .gif) { return "gif" }
        if type.conforms(to: .webP) { return "webp" }
        return type.preferredFilenameExtension
    }
}

struct AttachmentChipView: View {
    let draft: AttachmentDraft
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if case .uploading = draft.state {
                ProgressView()
                    .controlSize(.mini)
            } else if case .error = draft.state {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            } else if case .done = draft.state {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(draft.displayLabel)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if case .error(let message) = draft.state {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove \(draft.name)"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(
                draft.state.isError
                    ? Color.red.opacity(0.12)
                    : Color(.tertiarySystemFill)
            )
        )
    }
}

enum ContextMode: String, CaseIterable, Identifiable {
    case plan
    case draft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan: return "Plan"
        case .draft: return "Draft"
        }
    }

    var systemImage: String {
        switch self {
        case .plan: return "checklist"
        case .draft: return "circle.dashed"
        }
    }
}

struct ContextModeRow: View {
    let mode: ContextMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 24)

                Text(mode.title)
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum ContextAddKind {
    case photos, screenshots, camera, files

    var title: String {
        switch self {
        case .photos: return "Photos"
        case .screenshots: return "Screenshots"
        case .camera: return "Camera"
        case .files: return "Files"
        }
    }

    var systemImage: String {
        switch self {
        case .photos: return "photo"
        case .screenshots: return "square.dashed"
        case .camera: return "camera"
        case .files: return "folder"
        }
    }

    var showsChevron: Bool {
        self == .screenshots
    }

    static let photos = ContextAddKind.photos
    static let screenshots = ContextAddKind.screenshots
    static let camera = ContextAddKind.camera
    static let files = ContextAddKind.files
}

struct ContextAddRow: View {
    let row: ContextAddKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: row.systemImage)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                Text(row.title)
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)

                Spacer()

                if row.showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// UIImagePickerController wrapper for the Camera row.
struct CameraImagePicker: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraImagePicker
        init(parent: CameraImagePicker) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }
    }
}

#Preview {
    ContextAttachView(attachments: .constant([]))
}
#endif
