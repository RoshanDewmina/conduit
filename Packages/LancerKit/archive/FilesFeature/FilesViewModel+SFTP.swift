#if os(iOS)
import SwiftUI
import Observation
import SSHTransport
import LancerCore
import UniformTypeIdentifiers

@MainActor @Observable
public final class SFTPFilesViewModel {
    public var currentPath: String
    public var entries: [SFTPEntry] = []
    public var isLoading: Bool = false
    public var error: String?
    public var selectedFileData: Data?
    public var selectedFileName: String?
    public var isShowingTextPreview: Bool = false
    public var transferProgress: FileTransferProgress?
    public var transferMessage: String?
    public var exportDocument: ExportedFileDocument?
    public var isShowingExporter: Bool = false

    private let sftp: SFTPClient

    public init(sftp: SFTPClient, initialPath: String = ".") {
        self.sftp = sftp
        self.currentPath = initialPath
    }

    public func reload() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            entries = try await sftp.list(path: currentPath)
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func navigate(to entry: SFTPEntry) async {
        if entry.isDirectory {
            currentPath = entry.path
            await reload()
        } else {
            do {
                selectedFileData = try await sftp.read(path: entry.path, limitBytes: 512 * 1024)
                selectedFileName = entry.name
                isShowingTextPreview = true
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    public func upload(localFileURL: URL) async {
        do {
            transferMessage = "Uploading \(localFileURL.lastPathComponent)…"
            transferProgress = .init(bytesTransferred: 0, totalBytes: nil)
            let remotePath = join(parent: currentPath, child: localFileURL.lastPathComponent)
            try await sftp.upload(localFileURL: localFileURL, to: remotePath) { [weak self] progress in
                Task { @MainActor in self?.transferProgress = progress }
            }
            transferMessage = nil
            transferProgress = nil
            await reload()
        } catch {
            transferMessage = nil
            transferProgress = nil
            self.error = error.localizedDescription
        }
    }

    public func download(entry: SFTPEntry) async {
        guard !entry.isDirectory else { return }
        do {
            transferMessage = "Downloading \(entry.name)…"
            transferProgress = .init(bytesTransferred: 0, totalBytes: entry.sizeBytes.map(Int64.init))
            let data = try await sftp.download(path: entry.path, onProgress: { [weak self] progress in
                Task { @MainActor in self?.transferProgress = progress }
            })
            exportDocument = ExportedFileDocument(
                filename: entry.name,
                data: data
            )
            isShowingExporter = true
            transferMessage = nil
            transferProgress = nil
        } catch {
            transferMessage = nil
            transferProgress = nil
            self.error = error.localizedDescription
        }
    }

    public func delete(entry: SFTPEntry) async {
        do {
            if entry.isDirectory {
                try await sftp.rmdir(path: entry.path)
            } else {
                try await sftp.remove(path: entry.path)
            }
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func rename(entry: SFTPEntry, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let destination = join(parent: currentPath, child: trimmed)
            try await sftp.rename(from: entry.path, to: destination)
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func createDirectory(named directoryName: String) async {
        let trimmed = directoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await sftp.mkdir(path: join(parent: currentPath, child: trimmed))
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func chmod(entry: SFTPEntry, modeOctal: String) async {
        let trimmed = modeOctal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let value = UInt32(trimmed, radix: 8) else {
            self.error = "Mode must be octal (example: 755)."
            return
        }
        do {
            try await sftp.chmod(path: entry.path, mode: value)
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func navigateUp() async {
        guard currentPath != "/" && currentPath != "." && currentPath != "~" else { return }
        let parent = (currentPath as NSString).deletingLastPathComponent
        currentPath = parent.isEmpty ? "/" : parent
        await reload()
    }

    private func join(parent: String, child: String) -> String {
        if parent.isEmpty || parent == "." { return "./\(child)" }
        if parent == "/" { return "/\(child)" }
        if parent.hasSuffix("/") { return "\(parent)\(child)" }
        return "\(parent)/\(child)"
    }
}

public struct ExportedFileDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.data] }

    public let filename: String
    public let data: Data

    public init(filename: String, data: Data) {
        self.filename = filename
        self.data = data
    }

    public init(configuration: ReadConfiguration) throws {
        self.filename = "file"
        self.data = configuration.file.regularFileContents ?? Data()
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
