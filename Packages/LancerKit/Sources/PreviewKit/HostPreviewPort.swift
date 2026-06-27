import Foundation

/// Validation shared by the host-preview UI and tests. Previews are always
/// loopback forwards to a port on the selected SSH host; this type deliberately
/// does not represent arbitrary remote URLs.
public enum HostPreviewPort {
    public static func isValid(_ port: Int) -> Bool {
        (1...65_535).contains(port)
    }

    public static func parse(_ text: String) -> Int? {
        guard let port = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), isValid(port) else {
            return nil
        }
        return port
    }
}

/// Browser policy for host previews. Only loopback URLs may render in the
/// embedded view; everything else is an external link.
public enum HostPreviewNavigation {
    public static func isEmbeddedPreviewURL(_ url: URL) -> Bool {
        if url.scheme == "lancer-preview" { return true }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
        return ["127.0.0.1", "localhost", "::1"].contains(url.host?.lowercased() ?? "")
    }
}
