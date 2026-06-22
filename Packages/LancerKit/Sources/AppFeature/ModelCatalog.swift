#if os(iOS)
import Foundation

// MARK: - ModelCatalog
//
// Per-vendor model options for the composer's model picker. ponytail: a static
// table, not a daemon `models.list` RPC — vendor model lists are small and change
// rarely, so a constant table is the lazy correct choice. If models start drifting
// per-host or per-account, add an agent.models.list RPC and source from it instead.

enum ModelCatalog {
    struct Model { let id: String; let label: String }

    static func models(for vendor: String) -> [Model] {
        switch vendor {
        case "claudeCode":
            return [
                Model(id: "claude-opus-4", label: "Claude Opus 4"),
                Model(id: "claude-sonnet-4", label: "Claude Sonnet 4"),
                Model(id: "claude-haiku-4", label: "Claude Haiku 4"),
            ]
        case "codex":
            return [
                Model(id: "openai/gpt-5-codex", label: "GPT-5 Codex"),
                Model(id: "openai/gpt-5", label: "GPT-5"),
            ]
        case "opencode":
            return [
                Model(id: "openrouter/deepseek/deepseek-v4-flash", label: "DeepSeek V4 Flash"),
                Model(id: "opencode/mimo-v2.5-free", label: "MiMo V2.5 (free)"),
            ]
        case "kimi":
            return [Model(id: "kimi-code/kimi-for-coding", label: "Kimi K2.7 Code")]
        case "openrouter":
            return [
                Model(id: "claude-sonnet-4", label: "Claude Sonnet 4"),
                Model(id: "openai/gpt-5-codex", label: "GPT-5 Codex"),
                Model(id: "google/gemini-2.5-pro", label: "Gemini 2.5 Pro"),
                Model(id: "openrouter/deepseek/deepseek-v4-flash", label: "DeepSeek V4 Flash"),
                Model(id: "kimi-code/kimi-for-coding", label: "Kimi K2.7 Code"),
            ]
        default:
            return []
        }
    }

    /// Friendly label for a model id (falls back to the id itself).
    static func label(for id: String) -> String {
        for vendor in ["claudeCode", "codex", "opencode", "kimi", "openrouter"] {
            if let m = models(for: vendor).first(where: { $0.id == id }) { return m.label }
        }
        return id
    }
}
#endif
