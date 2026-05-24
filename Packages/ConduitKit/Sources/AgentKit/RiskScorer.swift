import Foundation
import ConduitCore

/// Static, local-only risk scorer for proposed shell commands. Used in the
/// Inbox to colour-band approval cards. The rules are intentionally dumb
/// and conservative — we never silently auto-reject; the user is always in
/// the loop. Bands are advisory.
public enum RiskScorer {
    public static func score(command: String, cwd: String = "~") -> Approval.Risk {
        let c = command.lowercased()

        // Critical: irreversible, broad blast radius.
        let critical: [String] = [
            "rm -rf /", ":(){:|:&};:",
            "mkfs", "dd if=", "shred ",
            "drop database", "truncate table",
            "kubectl delete ns ", "kubectl delete namespace",
            "terraform destroy", "aws s3 rm --recursive",
            "git push --force origin main", "git push -f origin main",
            "git push --force-with-lease origin main",
        ]
        if critical.contains(where: { c.contains($0) }) { return .critical }

        // High: writes, deletes, sudo, redirects to system paths.
        let high: [String] = [
            "sudo ", "rm -r", "rm -rf", "mv /", " /etc/", " /var/log/",
            "chmod 777", "chown root", "pkill -9", "kill -9 -1",
            "git reset --hard origin/", "git push --force",
            "kubectl apply", "helm uninstall",
        ]
        if high.contains(where: { c.contains($0) }) { return .high }

        // Medium: installs, builds, schema-ish.
        let medium: [String] = [
            "npm install", "pnpm install", "yarn install", "bun install",
            "pip install", "uv add", "cargo install", "go install",
            "apt install", "brew install", "apk add",
            "alembic upgrade", "prisma migrate", "drizzle-kit",
            "docker run", "docker compose up", "make ", "cmake ",
            "git commit", "git push",
        ]
        if medium.contains(where: { c.contains($0) }) { return .medium }

        // Default low for read-only.
        return .low
    }
}
