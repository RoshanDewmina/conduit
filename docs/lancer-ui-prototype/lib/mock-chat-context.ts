export type MockMachine = {
  id: string
  name: string
  online: boolean
  agentCount: number
}

export type MockWorkspace = {
  path: string
  label: string
}

export type MockModel = {
  id: string
  label: string
  vendorLabel: string
}

export const MOCK_MACHINES: MockMachine[] = [
  { id: "m1", name: "hermes-box", online: true, agentCount: 3 },
  { id: "m2", name: "Dev VPS", online: true, agentCount: 1 },
  { id: "m3", name: "Raspberry Pi", online: false, agentCount: 1 },
]

export const MOCK_WORKSPACES: MockWorkspace[] = [
  { path: "~/Documents/command-center", label: "command-center" },
  { path: "~/Documents/conduit-push", label: "conduit-push" },
  { path: "~/.hermes/knowledge-base", label: "knowledge-base" },
]

export const MOCK_MODELS: MockModel[] = [
  { id: "auto", label: "Auto (agent default)", vendorLabel: "" },
  { id: "opus", label: "Opus 4.8", vendorLabel: "Claude Code" },
  { id: "sonnet", label: "Sonnet 5", vendorLabel: "Claude Code" },
  { id: "gpt55", label: "GPT-5.5", vendorLabel: "Codex" },
]

export const CURRENT_SELECTION = {
  machine: MOCK_MACHINES[0],
  workspace: MOCK_WORKSPACES[0],
  model: MOCK_MODELS[1],
}
