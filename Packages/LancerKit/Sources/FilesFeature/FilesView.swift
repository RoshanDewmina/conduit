#if os(iOS)
import SwiftUI
import DesignSystem

public struct FilesView: View {
    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var currentPath: String = "/"
    @State private var selectedFile: FileItem?
    @State private var showingPreview = false
    @State private var previewContent: String?
    @State private var sortBy: SortOption = .name
    @State private var sortAscending = true

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            DSDivider(.strong)
            toolbar
            DSDivider(.strong)
            fileList
        }
        .background(t.termBg)
        .sheet(isPresented: $showingPreview) {
            if let file = selectedFile, let content = previewContent {
                FilePreviewView(filename: file.name, content: content, path: file.path)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 0) {
                Text("files")
                    .font(.dsDisplayPt(22, weight: .bold))
                    .foregroundStyle(t.termText)
                Text("_")
                    .font(.dsDisplayPt(22, weight: .bold))
                    .foregroundStyle(t.accent)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            breadcrumb
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            Text("~/lancer").foregroundStyle(t.termText3)
            Text("›").foregroundStyle(t.accent)
            Text(currentPath).foregroundStyle(t.termText2)
        }
        .font(.dsMonoPt(11))
        .lineLimit(1)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            searchField
            Spacer(minLength: 8)
            sortButton
            refreshButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(t.termText3)
            TextField("search files", text: $searchText)
                .font(.dsMonoPt(13))
                .foregroundStyle(t.termText)
                .tint(t.accent)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 36)
        .background(t.termSurface)
        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                .strokeBorder(t.termBorder, lineWidth: 1))
    }

    private var sortButton: some View {
        Button {
            Haptics.selection()
            if sortBy == .name {
                sortAscending.toggle()
            } else {
                sortBy = .name
                sortAscending = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12))
                Text(sortBy == .name ? "name" : "date")
                    .font(.dsMonoPt(11, weight: .medium))
            }
            .foregroundStyle(t.termText2)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(t.termSurface)
            .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                    .strokeBorder(t.termBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var refreshButton: some View {
        Button {
            Haptics.selection()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(t.termText2)
                .frame(width: 36, height: 36)
                .background(t.termSurface)
                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                        .strokeBorder(t.termBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if filteredFiles.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredFiles) { file in
                        fileRow(file)
                        if file.id != filteredFiles.last?.id {
                            DSDivider(.soft, leadingInset: 52)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            DSIconView(.folder, size: 32, color: t.termText3)
            Text("no files")
                .font(.dsMonoPt(14, weight: .medium))
                .foregroundStyle(t.termText2)
            Text("browse remote directories via SFTP")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.termText3)
        }
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
    }

    private func fileRow(_ file: FileItem) -> some View {
        Button {
            Haptics.selection()
            selectedFile = file
            if file.isDirectory {
                currentPath = file.path
            } else {
                previewContent = file.content
                showingPreview = true
            }
        } label: {
            HStack(spacing: 12) {
                DSIconView(file.isDirectory ? .folder : .file,
                          size: 18,
                          color: file.isDirectory ? t.termAccent : t.termText2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.dsMonoPt(13, weight: .medium))
                        .foregroundStyle(t.termText)
                        .lineLimit(1)
                    if let size = file.size {
                        Text(formatSize(size))
                            .font(.dsMonoPt(10))
                            .foregroundStyle(t.termText3)
                    }
                }
                Spacer()
                if file.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(t.termText3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private var filteredFiles: [FileItem] {
        var files = mockFiles
        if !searchText.isEmpty {
            files = files.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        files.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            switch sortBy {
            case .name:
                return sortAscending ? a.name < b.name : a.name > b.name
            case .date:
                return sortAscending ? a.modified < b.modified : a.modified > b.modified
            }
        }
        return files
    }
}

// MARK: - Sort Option

public enum SortOption {
    case name, date
}

// MARK: - File Item

public struct FileItem: Identifiable {
    public let id = UUID()
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let size: Int64?
    public let modified: Date
    public let content: String?

    public init(
        name: String,
        path: String,
        isDirectory: Bool,
        size: Int64? = nil,
        modified: Date = .now,
        content: String? = nil
    ) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
        self.content = content
    }
}

// MARK: - Mock Data

nonisolated(unsafe) private let mockFiles: [FileItem] = [
    FileItem(name: "projects", path: "/projects", isDirectory: true, modified: .now.addingTimeInterval(-3600)),
    FileItem(name: "documents", path: "/documents", isDirectory: true, modified: .now.addingTimeInterval(-7200)),
    FileItem(name: ".ssh", path: "/.ssh", isDirectory: true, modified: .now.addingTimeInterval(-86400)),
    FileItem(name: "config.json", path: "/config.json", isDirectory: false, size: 2048, modified: .now.addingTimeInterval(-1800), content: "{\n  \"theme\": \"dark\",\n  \"fontSize\": 14\n}"),
    FileItem(name: "README.md", path: "/README.md", isDirectory: false, size: 4096, modified: .now.addingTimeInterval(-3600), content: "# Project\n\nA sample project."),
    FileItem(name: ".gitignore", path: "/.gitignore", isDirectory: false, size: 128, modified: .now.addingTimeInterval(-86400), content: "*.log\n.DS_Store"),
]

#endif
