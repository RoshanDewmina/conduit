#if os(iOS)
import SwiftUI
import Observation
import SSHTransport
import ConduitCore

@MainActor @Observable
public final class SFTPFilesViewModel {
    public var currentPath: String
    public var entries: [SFTPEntry] = []
    public var isLoading: Bool = false
    public var error: String?
    public var selectedFileData: Data?
    public var selectedFileName: String?
    public var isShowingTextPreview: Bool = false

    private let sftp: SFTPClient

    public init(sftp: SFTPClient, initialPath: String = "~") {
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

    public func navigateUp() async {
        let parent = (currentPath as NSString).deletingLastPathComponent
        currentPath = parent.isEmpty ? "/" : parent
        await reload()
    }
}
#endif
