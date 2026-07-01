# 07 — Chat and Agent Experience

> Source: Wave-2 chat/agent-interaction research (Mobbin full flows + product docs). Verdict: chat is a **depth surface and dispatch primitive**, not Lancer's home.

## Verdict

The home stays **Command Home** (attention, machines, running/background work, blocked approvals, governance state). This matches product truth: Lancer's differentiator is policy/audit/emergency-stop governance, with chat/terminal demoted to depth surfaces ([ARCHITECTURE.md:31](/Users/roshansilva/Documents/command-center/ARCHITECTURE.md), [ARCHITECTURE.md:251](/Users/roshansilva/Documents/command-center/ARCHITECTURE.md)).

## Lancer already has the right bones

- Home shows waiting approvals and machines, not a blank chat prompt ([LancerHomeView.swift:65](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/AppFeature/LancerHomeView.swift)).
- Sidebar has ChatGPT-style affordances: new chat, search, recent threads, pin/rename/archive/delete ([LancerSidebarView.swift:137](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/AppFeature/LancerSidebarView.swift)).
- New Chat already supports `/` commands, `@` file refs, agent/machine chips, model/budget options, inline approvals, terminal blocks, artifacts, follow-up, regenerate, stop, budget controls ([NewChatTabView.swift:380](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/AppFeature/NewChatTabView.swift), [NewChatTabView.swift:610](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/AppFeature/NewChatTabView.swift), [NewChatTabView.swift:752](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/AppFeature/NewChatTabView.swift)).
- The data model is run/work oriented: conversations carry `agentID`, `vendor`, `hostName`, `cwd`, `model`, `budgetUSD`, status; artifacts typed as tool/diff/file/test/preview/approval ([ChatConversation.swift:3](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/LancerCore/ChatConversation.swift), [ChatConversation.swift:102](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/LancerCore/ChatConversation.swift)).

## Competitive patterns (organized by what to borrow)

- **Discoverability (ChatGPT/Claude/Gemini/Copilot):** sidebar, recents, projects, attachments, model/tools near composer. *Borrow the affordances; copying their home makes Lancer look like a general AI assistant.* Mobbin: [ChatGPT sidebar](https://mobbin.com/screens/763a5d89-528d-45a5-9d51-e0cbaf526880), [Claude composer](https://mobbin.com/screens/974b2ea0-ac3d-4fc0-a8bc-0d04c43d38d2), [Gemini composer/model chip](https://mobbin.com/screens/793f47cc-ae07-4cfa-b36a-831db8d6d397), [Copilot sources/composer](https://mobbin.com/screens/fe9cc4ee-3a2c-47f4-a88c-b839e2aa50e7).
- **Visible work checklist (Perplexity):** the best consumer-AI borrowing — show "understanding/searching/considering/wrapping up/researched," adapted to **"planning/editing/testing/waiting/reviewing."** Mobbin: [Perplexity answer with process + sources](https://mobbin.com/screens/a494bfc9-f0cd-4776-bf0f-3aeb1022af9c).
- **Background developer agents (Codex mobile, GitHub Copilot agent):** explicit logs, diffs, tests, PRs, model choice, follow-up, active threads, approvals. ([OpenAI Codex from anywhere](https://openai.com/index/work-with-codex-from-anywhere/), [GitHub Copilot coding agent](https://docs.github.com/en/copilot/concepts/coding-agent/coding-agent))
- **Cursor:** queued follow-ups, tool visibility, terminal commands, browser checks, local checkpoints. ([Cursor agent overview](https://cursor.com/docs/agent/overview.md))
- **Linear (strongest model for Lancer):** issue/work ownership stays human, agent is delegated, session tied to the issue, PR/diff review explicit. ([Linear agents](https://linear.app/docs/agents-in-linear), [Linear coding sessions](https://linear.app/docs/coding-sessions))
- **Attention routing (Slack/Discord/iMessage):** jump-to/unread, channel hierarchy, pins. *Borrow attention routing, not the social-chat metaphor.* Mobbin: [Slack list](https://mobbin.com/screens/5a5d5e09-373b-4f7a-8b91-e1288f1aa275), [Discord channels](https://mobbin.com/screens/352b031b-d605-40bb-9d16-c425028011ee), [Messages pinned](https://mobbin.com/screens/81f3db72-0300-4b15-8360-f22c437ef0cb).

## Recommended UX

- **Rename visible "chat" moments where possible.** Primary CTA → **Start work** / **New run**; sidebar section → **Recent work**; search → **Search work, files, commands.** Keep "chat" only where it names the actual transcript.
- **Conversation list sorts by state first:** Needs you → Running → Failed → Done, then by machine/project. Pins mean "watch this," not "favorite."
- **Every thread header shows context chips:** agent, machine, repo/cwd, branch if known, policy mode, budget, model. Model switching lives in **Run settings**, not as the hero.
- **Working state = compact timeline:** `Queued → Planning → Reading files → Editing → Running tests → Waiting for approval → Summarizing`, with expandable tool/log details.
- **Long outputs default to summaries + artifact cards.** Logs stay searchable/copyable, truncation shown clearly, diff/test cards pinned above raw terminal output.
- **Completion summary always answers:** what changed, tests run, files touched, approvals asked, risk/budget consumed, next action.
- **Failure/reconnect states are product-grade:** "Disconnected, agent still running on host," "Retry from last safe point," "No changes applied," "Approval denied; action blocked."
- **Parallel/background work lives on Home and Machines** (counts, blockers, newest proof artifact, emergency stop). The transcript steers one run; it does not manage the fleet.

## Why the current app reads as a Claude clone — and the fix

Claude/ChatGPT are "ask an assistant." Lancer should read as **"supervise work on my machines."** Keep chat *grammar* (familiar, usable input) but change the *noun hierarchy*:

| Layer | Claude mobile | Lancer |
|---|---|---|
| Home | New-chat prompt | Operational Command Home |
| Sidebar | Conversations | Work inventory (runs, machines) |
| Composer | Ask | Dispatch / control |
| Messages | Assistant replies | Run turns |
| Outputs | Prose answers | Evidence cards (diff/test/file/approval) |

Keep the chat input because it's usable; make the surrounding frame governance-first so the product does not visually or conceptually collapse into Claude mobile.

## Source queries (Mobbin)

`ChatGPT conversation history sidebar with search chats and new chat button`; `Claude chat home with conversation list search and new chat composer`; `Perplexity answer screen with sources citations and follow up composer`; `Google Gemini mobile chat screen with model picker and attachments`; `Microsoft Copilot mobile chat screen with sources follow up composer`; `Slack mobile channel list search unread threads`; `Discord mobile server channel list unread mentions`; `Apple Messages conversation list pinned messages search`; `Cursor agent chat composer terminal tool output code changes`.
