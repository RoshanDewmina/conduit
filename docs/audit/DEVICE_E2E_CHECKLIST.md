# Device E2E Verification Checklist

> Turnkey checklist for the on-device session that closes the gaps the headless
> simulator cannot verify. Every item here is **blocked in the sim** because it
> needs (a) a live agent/daemon connection, (b) real taps, or (c) a widget host.
> Run on a physical iPhone with a real paired host (`conduitd` running).
>
> Status legend: ☐ not run · ✅ pass · ❌ fail (note what you saw)

## Pre-flight
- ☐ `conduitd` resident running on the host (`launchctl kickstart -k gui/$(id -u)/dev.conduit.conduitd` on this Mac, or the host's installer).
- ☐ Phone and host reachable over the relay (or same LAN for SSH).
- ☐ Fresh install (delete app first) so you see real first-run, not seeded state.

## A. First-run + pairing (real, not gallery)
- ☐ A1 Launch fresh → onboarding step 1 "Agents ask. You approve. Work resumes." renders.
- ☐ A2 "Get started" → step 2 shows a **real** 6-digit pairing code (not `482 917`/`584 227` mock) and "Waiting for the host to pair…".
- ☐ A3 Run the install/pair on the host → card flips to "Paired ✓" automatically (`pairingState == .paired`).
- ☐ A4 Step 3 policy: pick a tier (Cautious/Balanced/Bypass) → "Connect and finish".
- ☐ A5 **Policy push:** on first connect, confirm the chosen tier's starter `~/.conduit/policy.yaml` is written on the host (`cat ~/.conduit/policy.yaml` → matches the tier in `OnboardingPolicy.policyYAML`). This is the unverified-in-sim path.
- ☐ A6 Land on Fleet (or Inbox if something needs attention).

## B. Populated Fleet (sim shows only hosts/QuotaGuard — these need live agents)
- ☐ B1 With ≥1 live agent running, Fleet shows the **spend summary card** ($ today, runs, vendor breakdown bar, N/3 concurrent) — matches `refs/08-fleet.jpg`.
- ☐ B2 Live **agent rows** show status (working/waiting) + per-agent spend.
- ☐ B3 A waiting agent surfaces the "… is waiting for your decision" banner.
- ☐ B4 Tap a running agent → **task detail** shows status, streaming output, changed files/diff, CI/proof if any, and stop/continue/review actions.
- ☐ B5 Back to Fleet → "New task" composer asks for host, repo/folder, agent/provider, prompt, budget/guardrail.
- ☐ B6 Start a task → it appears in Fleet; any required approval appears in Inbox.

## C. Live approval loop (transport proven by unit tests; tap-to-decide needs device)
- ☐ C1 Trigger a risky agent action on the host → approval card appears in Inbox over the relay with agent/action/risk/reason.
- ☐ C2 Tap **Approve** on a low/medium action → host resumes; card moves to Inbox history.
- ☐ C3 Tap **Deny** on another → host reports denied.
- ☐ C4 Trigger a **critical** action → Face ID/biometric gate appears before the decision applies.
- ☐ C5 "Edit & run" → editing tool input before approving works.
- ☐ C6 "Allow always" → creates a scoped rule; the next identical action is auto-allowed.
- ☐ C7 Background the app → APNs push for a new approval reaches the lock screen.

## D. Activity / "while you were away" (sim shows empty "not connected")
- ☐ D1 After agents act while disconnected, the populated audit feed renders.
- ☐ D2 Entries show what each agent did + outcomes.

## E. Tap-gated sub-screens (no gallery route; reachable only by interaction)
- ☐ E1 **New Chat** composer (the "+" path) renders and matches design.
- ☐ E2 **Voice Input** dictation screen.
- ☐ E3 **Quota Rings** (tap the Quota Guard card) — ring viz + caps.
- ☐ E4 **Agent Worktree Detail** — drill-in from a task.

## F. Widget / system surfaces
- ☐ F1 **Live Activity** on the lock screen / Dynamic Island during a run (add a real run, lock the phone).
- ☐ F2 **Status widget** on the home screen.
- ☐ F3 Apple **Watch** approval + emergency-stop round-trip (if testing watch).

## G. Tester IA navigation tasks (run blind — see DEVICE_E2E_CHECKLIST §IA)
Ask a fresh tester to do each WITHOUT help; record which tab they open:
- ☐ G1 "Find approvals waiting for you." → expect **Inbox**
- ☐ G2 "Find what agents are running." → expect **Fleet**
- ☐ G3 "Change when agents need permission." → expect **Control** ⚠️ (today: Settings → Policy — see deviation report)
- ☐ G4 "Set a spend limit." → expect **Control** ⚠️ (today: Fleet → Quota Guard / Settings)
- ☐ G5 "Find old decisions." → expect **Inbox → History**
- ☐ G6 "Connect another computer." → expect **Settings → Connection** or Fleet add-state
- ☐ G7 "Stop all agents." → expect **Control → Emergency stop** ⚠️ (today: watch-only, no phone button)
- ☐ G8 "Find SSH keys." → expect **Settings → Advanced** ⚠️ (today: Settings → Security)
- ☐ G9 "Review changed files from a task." → expect **Fleet → task detail**
- ☐ G10 "Change notification quiet hours." → expect **Settings → Notifications** (today: Settings → Notification Filters)

> ⚠️ = current app deviates from the tester's expected IA. See
> `docs/audit/IA_CONFORMANCE_2026-06-17.md` for the gap analysis + plan.
