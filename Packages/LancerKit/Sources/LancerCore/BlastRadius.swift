import Foundation

public enum BlastSeverity: String, Codable, Hashable, Sendable, CaseIterable {
    case low
    case medium
    case high
}

public struct BlastRadius: Codable, Hashable, Sendable {
    public let affectedPaths: [String]
    public let commands: [String]
    public let severity: BlastSeverity
    public let touchesProduction: Bool

    public var affectedPathCount: Int { affectedPaths.count }

    public init(
        affectedPaths: [String] = [],
        commands: [String] = [],
        severity: BlastSeverity = .low,
        touchesProduction: Bool = false
    ) {
        self.affectedPaths = affectedPaths
        self.commands = commands
        self.severity = severity
        self.touchesProduction = touchesProduction
    }

    // MARK: - Heuristic derivation

    public static func derive(fromCommand command: String, cwd: String = ".") -> BlastRadius {
        let parts = command
            .split(separator: "&&")
            .flatMap { $0.split(separator: ";") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var paths: [String] = []
        var cmds: [String] = []
        var severity: BlastSeverity = .low
        var touchesProduction = false

        for part in parts {
            let tokens = part.split(separator: " ").map(String.init)
            guard let head = tokens.first else { continue }

            cmds.append(part)

            let base = head.split(separator: "/").last.map(String.init) ?? head

            switch base {
            case "rm":
                if tokens.contains("-rf") || tokens.contains("-r") || tokens.contains("-f") {
                    severity = max(severity, .high)
                } else {
                    severity = max(severity, .medium)
                }
                let pathArgs = tokens.dropFirst().filter { !$0.hasPrefix("-") }
                paths.append(contentsOf: pathArgs)

            case "git":
                let sub = tokens.dropFirst().first ?? ""
                switch sub {
                case "push":
                    severity = max(severity, .high)
                    if tokens.contains("--force") || tokens.contains("-f") {
                        touchesProduction = true
                    }
                case "reset":
                    severity = max(severity, .medium)
                case "commit", "merge", "rebase", "tag":
                    severity = max(severity, .low)
                default:
                    break
                }

            case "npm", "yarn", "bun", "pnpm":
                let sub = tokens.dropFirst().first ?? ""
                if sub == "run" {
                    let script = tokens.dropFirst(2).first ?? ""
                    let deployKeywords = ["deploy", "publish", "release", "ship", "prod"]
                    if deployKeywords.contains(where: { script.lowercased().contains($0) }) {
                        severity = max(severity, .high)
                        touchesProduction = true
                    } else {
                        severity = max(severity, .low)
                    }
                } else if sub == "publish" {
                    severity = max(severity, .high)
                    touchesProduction = true
                }

            case "curl", "wget", "ssh", "scp", "rsync":
                severity = max(severity, .medium)

            case "kubectl", "helm", "terraform", "ansible", "pulumi":
                severity = max(severity, .high)
                touchesProduction = true

            case "docker":
                let sub = tokens.dropFirst().first ?? ""
                if ["push", "deploy"].contains(sub) {
                    severity = max(severity, .high)
                    touchesProduction = true
                } else {
                    severity = max(severity, .medium)
                }

            case "cp", "mv":
                let pathArgs = tokens.dropFirst().filter { !$0.hasPrefix("-") }
                paths.append(contentsOf: pathArgs)
                let isOutsideSrc = pathArgs.contains(where: isOutsideSourceDir)
                severity = max(severity, isOutsideSrc ? .medium : .low)

            case "chmod", "chown", "sudo":
                severity = max(severity, .high)

            case "make":
                let target = tokens.dropFirst().first ?? ""
                let deployKeywords = ["deploy", "release", "publish", "prod"]
                if deployKeywords.contains(where: { target.lowercased().contains($0) }) {
                    severity = max(severity, .high)
                    touchesProduction = true
                } else {
                    severity = max(severity, .low)
                }

            default:
                break
            }
        }

        // Paths written outside common source dirs elevate severity
        let outOfSrc = paths.filter(isOutsideSourceDir)
        if !outOfSrc.isEmpty {
            severity = max(severity, .medium)
        }

        return BlastRadius(
            affectedPaths: Array(OrderedSet(paths)),
            commands: cmds,
            severity: severity,
            touchesProduction: touchesProduction
        )
    }
}

// MARK: - Helpers

private func isOutsideSourceDir(_ path: String) -> Bool {
    let safe = ["src/", "Sources/", "lib/", "app/", "build/", "dist/", ".build/", "tests/", "test/", "spec/"]
    let normalized = path.hasPrefix("./") ? String(path.dropFirst(2)) : path
    if normalized.hasPrefix("/") { return true }
    return !safe.contains(where: { normalized.hasPrefix($0) || normalized == $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) })
}

private func max(_ a: BlastSeverity, _ b: BlastSeverity) -> BlastSeverity {
    let order: [BlastSeverity] = [.low, .medium, .high]
    let ia = order.firstIndex(of: a) ?? 0
    let ib = order.firstIndex(of: b) ?? 0
    return order[Swift.max(ia, ib)]
}

// Minimal ordered-unique collection to preserve insertion order while deduplicating paths
private struct OrderedSet<Element: Hashable>: Sequence {
    private var seen = Set<Element>()
    private var elements: [Element] = []

    mutating func append(_ element: Element) {
        guard seen.insert(element).inserted else { return }
        elements.append(element)
    }

    mutating func append<S: Sequence>(contentsOf seq: S) where S.Element == Element {
        seq.forEach { append($0) }
    }

    init(_ seq: [Element] = []) {
        seq.forEach { append($0) }
    }

    func makeIterator() -> IndexingIterator<[Element]> { elements.makeIterator() }
}
