# Projects / workspaces as a first-class concept — design exploration

> Status: brainstorm / planning document. No code changes proposed or made. Grounds every claim
> in current code (file:line) as of 2026-07-02. Supersedes nothing — `ARCHITECTURE.md` §0.1/§4.1
> remain the IA source of truth; this document is a candidate addition to that model, pending
> the owner decisions in §7.
>
> Starting direction taken as given (not re-litigated here, per a prior owner conversation):
> **the literal `cwd` path is the canonical identity of a project; a display name is a cosmetic
> overlay**, persisted the same way machine display names are today.

---

## 1. Problem statement — what's actually missing today

Lancer has no first-class "project" entity. What exists is a `cwd` string threaded through five
different places, each with its own (slightly different) idea of identity:

- **`ChatConversation`** (`Packages/LancerKit/Sources/LancerCore/ChatConversation.swift:1-53`) has
  `hostName: String`, `hostID: String?`, and `cwd: String` fields, persisted verbatim as text
  columns by `ChatConversationRepository` (`Packages/LancerKit/Sources/PersistenceKit/ChatConversationRepository.swift:30-45`,
  GRDB/SQLite). No normalization happens before the `INSERT` — whatever string the composer had
  is what lands in the `cwd` column.
- **`FleetThreadMapper.findConversation`** (`Packages/LancerKit/Sources/AppFeature/FleetThreadMapper.swift:7-25`)
  is the closest thing to "which project is this" grouping that exists: it matches a
  `(hostName, agentID, cwd)` triple by **exact string equality**, with a legacy-suffix fallback
  for `hostName` only (`conv.hostName.hasSuffix(" · \(hostName)")`, for pre-V1 conversations that
  stored a combined display name). This is the natural ancestor of "which project does this
  session belong to" — but it re-derives the grouping ad hoc on every call rather than persisting
  a project entity, and it keys on the **mutable** `hostName`, not the stable `hostID`.
- **`LancerHomeView`'s `machines` computed property** (`Packages/LancerKit/Sources/AppFeature/LancerHomeView.swift:502-561`)
  already groups sessions two levels deep — host → project (`cwd`) → session — via
  `Dictionary(grouping: byHost[host] ?? [], by: \.cwd)` (line ~536) and a `HomeProject` struct
  (`path: String`, `sessions: [ChatConversation]`, line ~594-598) that is **already, informally,
  exactly the "project" concept the owner wants** — it's just synthesized fresh on every view
  render from `ChatConversation.cwd` strings, never a stored/named entity a user creates or owns.
- **`daemon/lancerd/session_index.go`'s `buildSessionIndex`** (lines 42-108) discovers sessions
  Lancer never dispatched at all — anything under `~/.claude/projects/**` (plus OpenCode/Codex/Kimi
  equivalents), tagging them `Source: "transcriptObserved"` or `"providerManaged"`. These show up
  in "Sessions on this Mac" with their own `cwd` (`SessionInfo.CWD`, line 26) sourced from the
  transcript's own recorded field (`inspectTranscript`, lines 221-272) — an **absolute path
  written by the vendor CLI itself**, not something Lancer chose.
- **The composer already has an ad-hoc, unnamed, unscoped version of "pick a project"**: the
  `/workspace` slash command (`NewChatTabView.swift:156,191`) opens a "Project drawer"
  (`showContextPicker`) with a quick-pick list (`projectDirs`, lines 862-876: selected agent's
  default `cwd`, every known agent's `cwd`, then `recentProjectPaths`) and a free-text
  `customWorkspaceEntry` field (line ~1360, placeholder `"~/projects/my-app"`). Picking or typing
  a path sets `selectedCwd`, remembered via `rememberProjectPath` (lines 1397-1405, capped at 8,
  deduped) into `@AppStorage("lancer.recentProjectPaths")` (line 100). **This `@AppStorage` key is
  global across the whole app, not scoped per machine** (lines 100, 103-105) — a real
  divergence from the "per-machine index" pattern this design is supposed to follow, and a
  concrete gap this design should close rather than carry forward silently (see §2, §6).

**Net problem:** a project is discovered, not created. It has no name a user chose, no
create/rename/delete lifecycle, no per-machine scoping, and no cross-device continuity guarantee
beyond "the cwd string happens to match." The rough proposal in the brief — pair a machine, name a
starting directory, have all future sessions in that directory (from either phone or laptop) land
under that named project — requires promoting `HomeProject`/`FleetThreadMapper`'s implicit grouping
into a persisted, named, per-machine entity.

A second, concrete, currently-latent bug this design must not inherit: **`cwd` string
representations don't agree with each other today.** A relay-dispatched agent's default `cwd` is
the **literal string `"~"`** (`AppRoot.swift:940,948` — every relay machine's `DispatchAgent`
entries default `cwd: "~"` until the user picks something in the Project drawer), and the daemon
only expands it at process-launch time via `expandHome` (`daemon/lancerd/dispatch.go:22-29`,
called inside `realLauncher`) — **not** before the string is echoed back and persisted into
`ChatConversation.cwd`. Meanwhile an *observed* session's `cwd` (from `session_index.go`'s
transcript scan) is always an absolute path, because that's what the vendor CLI itself wrote. So
today, a phone-dispatched conversation with `cwd == "~"` and an observed terminal session in the
same actual directory with `cwd == "/Users/roshan"` **already fail to match** under
`FleetThreadMapper`'s exact-string comparison — they'd become two different "projects" under any
naive path-identity scheme, despite being the same directory. There is **no path-normalization
utility anywhere in the codebase** (Swift or Go — confirmed by grep); this has to be built new,
not reused.

---

## 2. Core model — path is identity, name is overlay

### 2.1 The exact identifier

**Proposal:** the project identifier is the **expanded, absolute, trailing-slash-stripped path**,
computed once at the point a `cwd` first becomes a project candidate (creation time), using the
*daemon's* `expandHome` logic (or its Swift-side equivalent) — never the raw string a client
happened to type or a transcript happened to record.

Concretely, a `normalizeProjectPath(_ raw: String, homeDir: String) -> String` (needs both a Swift
implementation used at persistence boundaries — `NewChatTabView`'s `useCustomCwd`,
`ChatConversationRepository.createConversation` — and a Go one on the daemon side, or the daemon
sends the already-expanded path back to the phone and the phone stores that instead of its own
guess) that:

1. Expands a leading `~` to the **actual home directory of that specific machine** (not the
   phone's own home directory — machines can have different usernames/home paths). This means the
   expansion is inherently a **per-machine** operation: `~` on machine A and `~` on machine B are
   different absolute strings even though the literal input is identical. The daemon already knows
   its own home dir (`agentHomeDir()`, used throughout `session_index.go`) — the cleanest fix is
   to have the daemon report the **expanded** path back in every RPC result (`agent.dispatch`,
   `agent.sessions.list`) rather than have the phone re-derive it blind.
2. Strips a trailing `/` (`~/repo/` and `~/repo` must be the same project).
3. **Does NOT resolve symlinks by default.** Resolving symlinks would silently merge two
   user-intended-distinct checkouts (e.g. two git worktrees symlinked into a shared cache) into one
   project — worse than the alternative of occasionally treating a symlinked alias as a second
   project. This is called out as an explicit open question in §7, not silently decided.
4. Does NOT lowercase / case-fold. macOS's default filesystem is case-insensitive but
   case-*preserving*; a naive case-fold would break on a case-sensitive remote Linux box.

This identifier is **never shown to the user** — it is the join key only. Everything the user sees
is the display name (§2.2) or, absent one, the path's last component (already how
`NewChatTabView.lastPathComponent` derives a short label today, line ~840-843) or the normalized
path itself.

### 2.2 The overlay: per-machine, Keychain-shaped — with one flagged tension

The brief's own comparison point — `RelayFleetStore.updateDisplayName`, `RelayMachineMigration.writeIndex`
— is: read the whole array, mutate the matching element in memory, write the whole array back to
one Keychain item (`RelayMachineMigration.swift:79-90`; the write call sites are
`RelayFleetStore.swift:52-57` for rename, `:62-67` for add, `:73-81` for remove — all three end in
`Task { await RelayMachineMigration.writeIndex(records) }`, an **unstructured, uncoordinated
background write** with no debouncing).

Following that exact pattern for projects would mean: each `RelayMachineRecord` grows a
`var projects: [ProjectRecord]` field (`ProjectRecord { let path: String; var displayName: String;
let createdAt: Date; var lastSessionAt: Date? }`), and the whole `[RelayMachineRecord]` array —
now containing every machine's every project — gets re-serialized to the Keychain on every rename,
every add, every auto-create.

**This is the single structural tension the constraints ask to be honest about, and it is real:**
the machines-index pattern was designed for a hard cap of 3 records
(`relayFleetMaxMachines = 3`, `RelayMachineRecord.swift:27`) that change rarely (pair/unpair/rename
— human-paced actions). Projects are explicitly proposed to **auto-create on every unmatched
`cwd`** (per the owner's rough flow) — that is not human-paced. A single active-development day
against one machine could produce a dozen distinct project paths (repo root, three worktrees, two
scratch dirs, a subdirectory a user happened to `cd` into). Every one of those triggers a full
re-encode-and-Keychain-write of **the entire multi-machine index**, including machines the change
had nothing to do with. Given the writes are unstructured `Task {}` calls with no ordering
guarantee against each other, this both:

- **degrades** — Keychain writes are not free (`SecItemUpdate` round-trips through `securityd`);
  doing one per auto-created project is a different cost profile than doing one per human rename,
  and
- **races** — two auto-creates firing close together (e.g. a laptop and a phone dispatch into two
  different subdirectories of the same repo within the same second) can genuinely lose one, since
  both read-mutate-write the same array with no compare-and-swap.

**DECIDED (2026-07-02, owner call):** project persistence moves to GRDB/SQLite — the same store
`ChatConversationRepository` already uses — keyed by `(machineID, normalizedPath)` with a real
`UPDATE ... WHERE`, not a blob rewrite. Nothing about a project record (a path string + a cosmetic
name + timestamps) needs Keychain-grade protection the way a **pairing private key** does; Keychain
was the right choice for `RelayMachineRecord` because it lives alongside `E2ERelayClient`'s actual
secrets in the same service (`RelayMachineMigration.swift:16-19`), not because path/name data is
sensitive. "Same persistence shape as machines" from the original brief is honored at the UX/API
level (per-machine, user-renameable, same rename/cap affordances) — not literally (Keychain, one
array, one blob), which would not hold up once auto-create removes the human pacing that keeps the
3-machine index's churn low today. A hard per-machine project cap (§6) is still load-bearing and
still needs a number (§7 Q4) regardless of storage layer.

### 2.3 Relationship to `RelayMachineRecord`

Whichever storage layer wins, the **conceptual shape** does mirror the machine record:

```
RelayMachineRecord            ProjectRecord (proposed)
--------------------------    --------------------------
id: RelayMachineID             id: normalized path (no synthetic UUID —
                                    the brief's whole point is path-as-identity)
displayName: String            displayName: String?  (nil = show path)
pairedAt: Date                 createdAt: Date
lastConnectedAt: Date?          lastSessionAt: Date?
                                machineID: RelayMachineID (foreign key, not
                                    embedded — see §2.2 storage recommendation)
```

Using the normalized path itself as the primary key (scoped by `machineID`) rather than minting a
new UUID keeps faith with "path is canonical identity" — there is no separate identity to drift
out of sync with the path the way `hostID` can drift from `hostName` today (see §1: `hostID` is
populated correctly at creation, `AppRoot.swift:948`, but nothing ever re-derives it, and
`FleetThreadMapper` ignores it entirely in favor of the mutable `hostName` — an existing
inconsistency this design should not deepen by inventing a second surrogate key for projects).

---

## 3. Creation flow

### 3.1 Does pairing gate chat at all today?

Checked directly: onboarding (`onboardingSeen`, `AppRoot.swift:156`) is a **one-time** flag,
independent of machine pairing — a user can finish onboarding with zero paired machines and land on
Home/New Chat. But `dispatchAgents()` (`AppRoot.swift:902-960`) returns `[]` when there are no
fleet slots and no relay machines, and `canSend` (`NewChatTabView.swift:881`) requires
`selectedAgent != nil` — so the composer is *reachable* but **inert** without a paired machine.
There is no earlier point where a project could meaningfully attach to anything. This confirms the
brief's proposed order (pair → prompt for starting directory) is the only workable one; there's no
"start a chat first, pair later" path to design around today.

### 3.2 First pairing → project #1

Hook point: `E2ERelayPairingView`'s `onPaired` closure
(`Packages/LancerKit/Sources/SettingsFeature/E2ERelayPairingView.swift:10,21,62-63` — fires on
successful pairing, right before `dismiss()`). It's wired at two call sites:
`AppRoot.swift:579` (the first-pairing / onboarding-adjacent path) and `AppRoot.swift:786-788`
(Settings → Paired Machines → add another). Both ultimately call `addRelayMachine(client:record:env:)`.

Proposed flow: after `addRelayMachine` succeeds, check whether *this machine* has zero projects
(not whether the fleet as a whole does — see §3.3). If so, present a sheet: a text field
(placeholder matching the existing composer's `"~/projects/my-app"`,
`NewChatTabView.swift:~1367`) with a **"Recent directories" autocomplete section**.

**That autocomplete source does not exist today.** Confirmed by grep: there is no
`agent.recentDirectories` (or equivalent) RPC. The closest neighbors are `agent.sessions.list`
(the full discovered-session scan, expensive and history-shaped, not a lightweight MRU-of-directories
list) and the `@`-mention workspace file listing (`AppRoot.swift:1010`,
`loadWorkspaceFiles`/`loadFiles` — lists **children of a single already-known directory**, not
candidate top-level project roots). A real implementation needs a **new** daemon RPC — the
natural source is exactly what `buildSessionIndex` already computes (distinct `cwd` values across
`~/.claude/projects` + the other three vendors' session stores) deduplicated into a path list,
capped and sorted by recency. This is new daemon work, not a rewire of something existing, and
should be scoped explicitly in any implementation plan (not silently assumed to already exist).

If the user skips/dismisses without entering a path, there is no project #1 — machine shows in Home
via the existing zero-project-fallback path (`LancerHomeView.swift`'s `sshHostNames`/`relayMachines`
folding, lines 505-533) exactly as it does today, just with an empty project list instead of a
flat session list.

### 3.3 Second (and third) machine pairing

Per-machine scoping (§2) means **every** newly-paired machine gets its own "name a starting
directory" prompt when *it* has zero projects — this is not a fleet-wide gate that only fires
once. A user with machine A already fully set up should still be asked for machine B's starting
directory when B is paired, because B's home directory and repo layout are almost certainly
different from A's. Skipping the prompt for machine 2/3 (on the theory that "the user already
knows how this works") saves one tap but silently reintroduces the exact "0 projects, confusing
empty state" class of bug from §6.7 for every subsequent machine — recommend **always** prompting,
letting the user dismiss it if they genuinely want to add sessions from the terminal first and let
auto-create backfill projects later.

---

## 4. Grouping/discovery rules

**Algorithm:** exact match only, against the normalized path (§2.1) — **not** a prefix match.

Rationale, grounded in the existing `HomeProject`/`FleetThreadMapper` behavior: both already treat
`cwd` as an atomic grouping key with exact equality; introducing prefix semantics now would be new
behavior, not a formalization of what exists. It also avoids a hard ambiguity: given projects
`~/repo` and `~/repo-v2`, a naive `hasPrefix` check would (correctly) need a `/`-boundary guard
anyway, and once you add that guard, `~/repo/packages/foo` under an existing `~/repo` project
becomes a live design question with no obviously-correct default (see §6's nested-path entry) —
better to ship exact-match-only for V1 and let the *user* promote a busy subdirectory into its own
project explicitly (typing it into the Project drawer, same UX as any other new project), which
the auto-create-on-unmatched-cwd rule already covers for free.

**Retroactive bucketing of "Sessions on this Mac":** yes, by the same exact-match rule, once paths
are normalized consistently (§1's `"~"` vs absolute-path finding makes this a **prerequisite**, not
a nice-to-have — without normalization, most observed sessions would silently fail to match any
phone-created project and pile up in an "unfiled" bucket that defeats the point of the feature).
An observed session whose `cwd` doesn't match any existing project's normalized path becomes a
new project via the same auto-create rule dispatched sessions get (§1, §5) — this is what answers
the brief's explicit question ("what happens when `agent.sessions.list` discovers a directory
never paired as a Lancer project at all") — **auto-adopt**, not ignore or prompt, for consistency
with the rest of the model. The UI must then visually distinguish observed-only projects/sessions
from Lancer-dispatched ones (§6.8) so "a project silently exists because someone once ran `claude`
there" doesn't read as something the user consciously set up.

---

## 5. Cross-device continuation

Walking the owner's scenario — phone starts a session in project A, later the **same session**
needs to be continuable from the laptop, and vice versa — against what's actually built:

**Already-built plumbing that mostly gets this for free:**

- `agent.run.continue` → `dispatcher.continueRun` (`daemon/lancerd/dispatch.go:1130-1189`) already
  falls back to **phone-supplied** `(agent, cwd, model, budgetUSD)` (`continueFallback`,
  lines 1123-1129) whenever the daemon's in-memory `run` map doesn't have the run anymore (daemon
  restart, or — critically for this design — **a different device entirely**, since the in-memory
  map is per-daemon-process, not per-client). The comment at line 1112-1121 spells out exactly why:
  `"<vendor> --continue" resumes the most recent session in that directory` — meaning **`cwd` is
  already the de facto join key for "continue this project's conversation"** across whatever
  device asks. A laptop-initiated `agent.run.continue` for a runId the phone created, or vice
  versa, already works **today**, purely because both devices talk to the same one resident
  `lancerd` and the fallback is cwd-keyed, not device-keyed.
- For sessions started **directly at the terminal** (never Lancer-dispatched), `agent.observedSession.continue`
  → `resumeObservedSession` (`dispatch.go:1230+`) targets the **exact** `sessionId` + `cwd` +
  `vendor`, deliberately not "most recent in cwd" (doc comment lines 1214-1220: "a user can have
  multiple terminal sessions open in the same project directory and 'most recent' would silently
  target the wrong one"). This already gives exact-session continuation regardless of which device
  asks, because the phone/laptop both just need to know the `sessionId` — which `agent.sessions.list`
  already reports to whichever client asks.

**What a "project" label needs to add — and what's genuinely new:**

- **Nothing new is needed for the daemon-side continuation mechanics.** They're already
  device-agnostic because they're keyed by `runId`/`sessionId` + `cwd`, not by "which phone/laptop
  dispatched this."
- **What's new is entirely presentation-layer:** the phone needs to *discover* that a laptop-
  initiated session exists in project A at all. Today that discovery is `agent.sessions.list`
  (a flat, unfiltered scan) surfaced as "Sessions on this Mac" — this design's job is to bucket
  that flat list under the matching `ProjectRecord` (§4) so it reads as "3 sessions in **Project A**"
  rather than an undifferentiated pile. That's a client-side (`LancerHomeView`) grouping change, not
  a protocol change.
- **One real gap:** cwd-string inconsistency (§1) breaks the join **today**, silently. Any phone-
  dispatched conversation whose `cwd` was left at the relay default `"~"` (never normalized) will
  not match a laptop-observed session's absolute-path `cwd`, even though `continueRun`'s fallback
  mechanism works fine underneath. Normalizing at the boundary (§2.1) is a prerequisite for the
  *visible* cross-device story, even though the underlying continue/resume RPCs don't strictly
  need it.

---

## 6. Edge cases and one-off scenarios

**Renaming a project after it has sessions.** Per §2.1/§2.3, the identifier is the path, not a
UUID — a rename only changes the cosmetic overlay field, never touched by any grouping/matching
logic. History (all `ChatConversation` rows whose `cwd` matches) stays attached automatically,
*for free*, because nothing about matching depends on the name. This is a genuine advantage of the
path-is-identity decision over a synthetic-ID scheme, worth stating positively.

**Deleting/unpairing a machine with 3 named projects.** `RelayFleetStore.remove` (`RelayFleetStore.swift:73-81`)
already deletes the machine's Keychain pairing entirely (`E2ERelayClient.deleteStoredPairing`) —
unrecoverable by design (matches how SSH host removal works today). Projects belonging to that
machine (however stored, §2.2) should be deleted alongside it — there is no meaningful "orphaned
project" state once the machine itself is gone (nothing can dispatch into it, and the daemon that
would answer `agent.sessions.list` for it no longer exists as a pairable target). The
**conversations** (`ChatConversation` rows) are a separate question: they're stored in the app's
own GRDB database, not the machine's Keychain entry, so they don't automatically disappear when
the machine is unpaired. Recommend: keep them, read-only, labeled with the machine's last-known
display name (same as today — nothing currently deletes `ChatConversation` rows on unpair either,
this isn't new behavior this design introduces).

**Two machines, same literal path** (e.g. the same repo cloned on two Macs). Per §2.2's per-machine
scoping, these are unambiguously **two separate `ProjectRecord`s** — the path is only unique
*within* a machine's project list, never globally. This falls directly out of "path is identity"
being **per-machine** (a design point implicit in the brief's own comparison to
`RelayMachineRecord`, which is itself per-machine). UI disambiguation: the same problem the
just-fixed `LancerHomeView` bug (§1, commit `acbbf76a`) solved for machine names applies identically
here — **never key a UI row by the display string**; key by `(machineID, path)` and let two
identically-named/identically-pathed projects render as two rows, disambiguated by which machine
section they're nested under (machine name is already the outer grouping level in `HomeMachine` →
`HomeProject`, so this is naturally solved by the existing two-level tree, *provided* the
implementation doesn't collapse on name/path equality the way the pre-fix `LancerHomeView` did on
`hostName` equality).

**A path renamed/moved on disk after project creation** (git worktree removed, directory renamed).
Lancer has no filesystem watcher and no daemon-side "does this path still exist" check today. The
project entry goes stale silently — its sessions still show (historical, correctly), but a fresh
dispatch attempt into it will fail at the shell level (`cd` to a nonexistent directory, or the
vendor CLI erroring). Recommend surfacing this **reactively**, not proactively: when a dispatch/
continue into a project's path errors in a way that looks like "directory not found" (the daemon
already returns freeform `Message` strings on `dispatchResult.Status == "error"` —
`dispatch.go:1183-1186`), the client should recognize that shape and offer "This directory may no
longer exist — remove this project?" rather than silently retrying or leaving the user staring at
an opaque shell error. A proactive daemon-side `stat` check on every Home render would be simple
but adds latency and a new RPC round-trip for a state change that's rare; reactive-on-error is
cheaper and sufficient for V1.

**Nested paths** (`~/repo` project exists, session starts in `~/repo/packages/foo`). Per §4:
**separate project**, not auto-folded, not a child-project hierarchy. A user who wants
`packages/foo` treated as part of `~/repo` can rename/merge manually (out of scope for V1 — see
§8) or simply always dispatch against `~/repo` from the Project drawer. Explicitly flagged as an
open question in §7 in case the owner disagrees with defaulting to "separate."

**3-machine cap interacting with per-machine project caps.** Per §2.2, auto-create removes the
human pacing that keeps the machine cap meaningful at 3 — a sane per-machine project cap is
**load-bearing**, not cosmetic, for whichever storage layer is chosen. Recommend a default cap in
the 15-25 range per machine (generous enough to cover a real multi-repo dev setup, small enough
that hitting it is a meaningful signal rather than routine), with the same "reached cap, here's why,
here's how to clear stale ones" messaging pattern the 3-machine cap just got in the §6.7 fix below
— not a bare refusal.

**The current "0 projects" / "Relay host" stale-entry class of bug** (`docs/KNOWN_ISSUES.md` §6, P1,
found+fixed 2026-07-02: `RelayMachineMigration`'s Keychain index survives app uninstall, so stale
paired-but-unreachable machines silently ate the 3-machine cap while `FleetView` simultaneously
rendered "no machines paired" — two contradicting empty states from the same underlying data).
**This design does not eliminate that bug class — it adds a second instance of it.** A project
list has exactly the same "stale entry survives reinstall, contradicts what another screen shows"
shape the machine list just got bitten by, *unless* the same fix pattern (an explicit
"offline/unreachable" distinction surfaced consistently everywhere the list renders, not a bare
count) is applied to projects from day one rather than retrofitted after a live bug report. Treat
the machine-list fix as the template to copy preemptively, not evidence the problem is solved.

**Mixed Lancer-dispatched + observed-only sessions in one project.** Yes, the UI needs to
distinguish these — `ChatConversation` (dispatched, gated per `LANCER_GATE`) and `ObservedSession`
(direct-terminal, ungated) are already different Swift types with different data available (an
`ObservedSession` has no `budgetUSD`, no `Status.archived`, etc. — `LancerDProtocol.swift:371-380`
vs `ChatConversation.swift:3-23`). `LancerHomeView` already renders them in visually distinct rows
today (`HomeProject.sessions: [ChatConversation]` vs the separate `observedSessions:
[ObservedSession]` array on `HomeMachine`, lines 594-599) — this design's job is to make sure that
distinction survives being nested one level deeper under a named project, not invent a new one.

**A directory `agent.sessions.list` discovers that was never paired as a Lancer project.**
Covered in §4: **auto-adopt**, consistent with the rest of the model, with a visual "discovered,
not manually created" marker (ties into the mixed-origin distinction above) so it doesn't read as
something the user consciously set up.

**Renaming clashes — two projects on the same machine given the identical display name.**
Directly mirrors the just-fixed machine-name-collision bug (`LancerHomeView.swift`, commit
`acbbf76a0077cd8002d5c45cc230a70d0ecaba71`, described in §1). The fix pattern there — **key UI
rows by the stable identifier (`RelayMachineID`), never by the mutable display string, and only
fold a new entry into an *existing* row when the name is the FIRST to claim it** — applies
identically here: project rows must be keyed by `(machineID, normalizedPath)`, never by
`displayName`, or two same-named projects on one machine will silently collapse into one row the
same way two same-named "Relay host" machines just did. This is the single clearest "don't
reintroduce a bug that was just fixed one level up" risk in the whole design, precisely because
the underlying data shape (an array of user-renameable records, keyed by a stable ID, sharing a
mutable display default) is the same shape being proposed for projects.

**Offline machine with a cached/stale project list.** Since project lists would live per-machine
(either embedded in the Keychain-stored `RelayMachineRecord` or a local GRDB table keyed by
`machineID`), the phone can always show the **last-synced** list even while the machine is offline
— same as it shows cached `installedAgentVendors` today (`RelayFleetStore.Machine.installedAgentVendors:
[String]?`, populated by `setInstalledAgentVendors`, `RelayFleetStore.swift:43-46`, and simply
`nil`/stale when never reported). Recommend the same non-blocking pattern: show the cached list
always, with a lightweight "last synced Xm ago" indicator only past some threshold (a few hours is
a reasonable default — a project list changes far less often than session state does, so staleness
here is much less urgent than the existing offline-session-state problem) rather than blocking the
UI or hiding stale data outright.

---

## 7. Open questions for the owner

1. ~~**Storage layer for the per-project overlay (§2.2).**~~ **DECIDED 2026-07-02: GRDB/SQLite**,
   keyed by `(machineID, normalizedPath)` — see §2.2 for the full reasoning. Not Keychain.
2. **Symlink resolution in path normalization (§2.1).** Resolve symlinks into the canonical
   identity (risk: silently merges user-intended-distinct paths) or leave them un-resolved (risk:
   a symlinked alias of the same real directory becomes a "different" project)? No default is
   obviously correct; flagged rather than assumed.
3. **Nested-path default (§6).** Confirm "separate project, no auto-fold, no hierarchy" is the
   right default for `~/repo/packages/foo` under an existing `~/repo` project, versus wanting some
   lightweight parent/child relationship later.
4. **Per-machine project cap value (§6).** A number is needed once auto-create ships; 15-25 was
   floated as a starting point, not a firm recommendation.
5. **Does unpairing a machine delete or archive its `ChatConversation` history?** Today unpairing
   doesn't touch the GRDB conversation rows at all (they're a separate store from the Keychain
   machine index) — is that the desired end state for a *project*-scoped view too (keep chat
   history readable forever, labeled with a now-defunct machine name), or should losing the
   machine also archive/hide its projects' history from the main Home view?
6. **Should "recently used custom paths" (today's global `@AppStorage("lancer.recentProjectPaths")`,
   `NewChatTabView.swift:100`) be deleted outright once real per-machine projects exist**, or kept
   as a separate "quick paths I've typed, regardless of machine" convenience layer alongside named
   projects? Keeping both risks user confusion between "a project" and "a path I once typed."

---

## 8. Phasing recommendation

This is a brainstorm/planning document; no code is proposed here. A rough MVP-vs-deferred split for
whoever scopes the implementation plan:

**MVP slice (closes the loop the brief describes):**
- Path normalization utility (§2.1), used consistently at every boundary that currently persists
  or compares a `cwd` (this is a prerequisite for everything else, including making today's
  `FleetThreadMapper`/`LancerHomeView` grouping correct, independent of projects shipping at all).
- `ProjectRecord` persistence, per-machine, keyed by `(machineID, normalizedPath)` — storage layer
  per the §7 Q1 decision.
- Pairing-flow prompt for a starting directory (§3.2), including the new
  daemon "recent directories" RPC it depends on.
- Grouping: exact-match bucketing of `ChatConversation` + `ObservedSession` under `ProjectRecord`s,
  with auto-create-on-unmatched-cwd (§4).
- Rename UI following the exact pattern `RelayMachinesListView`'s just-shipped machine-rename
  affordance uses, applied per-project.
- The mixed-origin (dispatched vs. observed) visual distinction (§6), since it already exists at
  the `HomeMachine` level and just needs to survive one more nesting level.
- Per-machine project cap + the "reached cap, here's why, here's how to clear stale ones" messaging
  (copying the just-fixed §6.7 pattern preemptively).

**Deferred / explicitly out of scope for MVP:**
- Any cross-machine "these are the same repo" reconciliation (§6's "same literal path, two
  machines" stays two separate projects, full stop — no smarter merge).
- Nested-path parent/child relationships (§7 Q3).
- Symlink-aware identity (§7 Q2) — ship un-resolved, revisit only if it causes real user-visible
  confusion.
- Deleting/archiving `ChatConversation` history on unpair (§7 Q5) — keep today's behavior
  (nothing touches it) until the owner decides otherwise.
- Any Siri/AppIntents surface for projects ("pause the X project," "which project is this approval
  from"). The currently-in-progress `CommandGateway`/`RunControlIntents` work
  (`.claude/worktrees/agent-a117187d4eaeaf0f6/Packages/LancerKit/Sources/SessionFeature/`, read-only,
  not modified for this doc) **explicitly punts on multi-run disambiguation today** —
  `resolveSoleActiveRun` (`RunControlIntents.swift:13-29`) acts only when exactly one run is active
  and returns "open Lancer to choose which one" otherwise, because `ActiveRunRegistry` only tracks
  bare run IDs — no cwd/project/machine metadata is visible from `SessionFeature`, which doesn't
  depend on `AppFeature` (module discipline, `docs/agent-contract.md` §1: "Features may depend on
  engines and `DesignSystem`, never on each other"). A project-aware Siri
  phrase needs either a new cross-module registry `SessionFeature` can read from directly, or an
  `AppEntity`/`EntityQuery`-based disambiguation flow — real new plumbing, not a label added to
  existing intents. Out of scope for the MVP slice above.
