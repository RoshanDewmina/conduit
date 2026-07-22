# L3 — Shell chrome (onboarding / Workspaces / composer / thread-list / review / empty-error)

**Date:** 2026-07-16  
**Auditor:** L3 Shell Chrome (daily-use audit)  
**Worktree tip:** `/Users/roshansilva/Documents/command-center/.worktrees/daily-use-audit-2026-07-16` @ `b17b6172`  
**Sim UDID:** `095F8B3A-FEA3-4031-A2A5-561755740730` (iPhone 17 Pro, Booted)  
**App:** `/tmp/daily-use-audit-dd/Build/Products/Debug-iphonesimulator/Lancer.app` (`dev.lancer.mobile`)  
**Pairing:** active relay code `583514` (L1 re-pair; not re-paired this lane)  
**Plan:** `docs/test-runs/2026-07-15-night-full-app-test-plan.md` §2, §5.1, §5.2, §5.3, §5.8, §5.10, §5.11  
**Evidence-only:** no product code changes.

**Daily-driver MVP lens (pieces 1–4):** pairing UI (1), thread list (2), chat (3), composer (4) — this lane covers shell surfaces that gate those pieces; chat transcript depth is L2.

---

## Results (PASS / FAIL / N-A)

| Check | Issue | Result | Daily-use note |
|-------|-------|--------|----------------|
| §2 Onboarding | #130 | **N-A** | Welcome not observed; sim already dogfooded — uninstall would risk pair `583514`. |
| §5.1 Composer morph | #120 | **FAIL** (partial UI) | Tap produced a real frame (`L3-02`); open/closed captures identical; morph vs sheet not proven clean. |
| §5.2 Thread-list rows | #121 | **BLOCKED** | `threadList` relaunch hung before `L3-03` screenshot. |
| §5.3 Review sheet | #122 | **N-A** | No dirty-thread / review deep-link exercised this session. |
| §5.8 Fake controls (mic) | #129 | **FAIL** | `mic.fill` still in tip composer source; L1-00 pill shows right-edge icon; removal claim false on build. |
| §5.10 Empty / loading / error | #133 | **PARTIAL** | Post-pair Workspaces hydrated (repo counts in a11y); no offline/daemon-kill error lane (sim hang). |
| §5.11 Thread-list filters | #134 | **BLOCKED** | No thread-list surface reached after simctl/idb wedged. |
| Profile Help → GitHub (#129 b) | #129 | **N-A** | Help row not tapped; Profile sheet seen briefly only. |

---

## Environment confirmation (session start)

```bash
xcrun simctl list devices booted
# iPhone 17 Pro (095F8B3A-FEA3-4031-A2A5-561755740730) (Booted)

pgrep -fl lancerd
# 81742 /Users/roshansilva/.lancer/bin/lancerd daemon

plutil -p "$(xcrun simctl get_app_container 095F8B3A-FEA3-4031-A2A5-561755740730 dev.lancer.mobile data)/Library/Preferences/dev.lancer.mobile.plist"
# relay code 583514, confirmed true — no onboardingSeen key present
```

---

## §2 — First-run onboarding (#130) — N-A

**Intent:** Launch without `-onboardingSeen YES` to surface `FirstRunOnboardingView`.

```bash
SS_DIR="docs/test-runs/2026-07-16-daily-use-audit/screenshots"
UDID="095F8B3A-FEA3-4031-A2A5-561755740730"
xcrun simctl terminate "$UDID" dev.lancer.mobile 2>/dev/null || true
sleep 1
xcrun simctl launch "$UDID" dev.lancer.mobile
sleep 3
xcrun simctl io "$UDID" screenshot "$SS_DIR/L3-00-onboarding-attempt.png"
```

**Screenshot:** `screenshots/L3-00-onboarding-attempt.png` — **~99.8% near-white** (captured before UI paint; mean pixel ≈ 254.6).

**A11y (after UI settled, same session):**

```bash
idb ui describe-all --udid 095F8B3A-FEA3-4031-A2A5-561755740730 | python3 -c "
import sys,json
d=json.load(sys.stdin)
print([x.get('AXLabel') for x in d if x.get('role')=='AXButton'][:12])
"
# ['Profile', 'Search', 'New Chat', 'All Repos, 1', 'daily-use-audit-2026-07-16, 1', 'Add Repo', 'New Chat']
# (counts varied later: All Repos, 50 / command-center, 30 / Home, 20)
```

**Finding:** No welcome / tier picker / “Pair your Mac” / “Set up later” labels in the accessibility tree. Landed on **Workspaces**, not onboarding.

**Why N-A (not PASS):** Plan §2 expects fresh install; this sim install is post-L1 (`-onboardingSeen YES` used there). `onboardingSeen` is absent from `dev.lancer.mobile.plist`, yet onboarding did not show — likely prior in-app skip or race. **Uninstall+reinstall** was not run to avoid orphaning relay pair `583514`.

**Missing for daily use:** First-run story unverified on this device; new users cannot be signed off from this evidence alone.

---

## §5.1 — Composer morph (#120) — FAIL (partial)

**Closed pill (usable frame):**

```bash
xcrun simctl terminate "$UDID" dev.lancer.mobile; sleep 1
xcrun simctl launch "$UDID" dev.lancer.mobile
sleep 4
xcrun simctl io "$UDID" screenshot "$SS_DIR/L3-01b-workspaces-clean.png"
```

`screenshots/L3-01b-workspaces-clean.png` (large PNG; UI painted). Bottom composer crop: `screenshots/L3-04-workspaces-composer-crop.png`.

**A11y — home composer entry (accessibility label “New Chat”; visible copy includes “Plan, ask, build…” per `WorkspacesView.swift`):**

```bash
idb ui describe-all --udid "$UDID" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for x in d:
    if x.get('role')=='AXButton':
        f=x.get('frame',{})
        print(x.get('AXLabel'), int(f.get('x',0)+f.get('width',0)/2), int(f.get('y',0)+f.get('height',0)/2))
"
# … New Chat 201 807
```

**Open attempt (tap pill center):**

```bash
idb ui tap --udid "$UDID" 201 807
sleep 2
xcrun simctl io "$UDID" screenshot "$SS_DIR/L3-02-composer-morph-open.png"
idb ui tap --udid "$UDID" 50 400
sleep 1
xcrun simctl io "$UDID" screenshot "$SS_DIR/L3-02b-composer-morph-closed.png"
```

**Evidence:**

- `L3-02-composer-morph-open.png` — non-blank (mean ≈ 236.8); **top 15% of frame has heavy ink** (≈60k sub-threshold pixels) — consistent with a **sheet/grabber** presentation, not a clean in-place morph proof.
- `md5 L3-02-composer-morph-open.png` == `md5 L3-02b-composer-morph-closed.png` (`886c120123c7b53a61fad104d6f79105`) — dismiss tap did not change the captured surface.
- Early `L3-01-workspaces-home.png` is blank (same whiteness as `L3-00`) — not used for morph verdict.

**Missing for daily use:** Cannot confirm §5.1 “grows upward over the list, no grab handle” from this session; composer expand/collapse UX unproven.

---

## §5.2 — Thread-list rows (#121) — BLOCKED

**Attempted:**

```bash
xcrun simctl terminate "$UDID" dev.lancer.mobile 2>/dev/null || true
sleep 1
env SIMCTL_CHILD_LANCER_DESTINATION=threadList xcrun simctl launch "$UDID" dev.lancer.mobile
sleep 5
xcrun simctl io "$UDID" screenshot "$SS_DIR/L3-03-thread-list.png"
```

**Outcome:** `simctl terminate` / subsequent `simctl io` / `idb ui describe-all` **hung** (no `L3-03` file created). Session blocker below.

**Missing for daily use:** Diff stats, liveness, unread dot, preview on rows — all unverified live.

---

## §5.3 — Review sheet (#122) — N-A

No thread with local changes opened; `LANCER_DESTINATION=review` not completed (blocked by simulator hang). L1 transcript run edited no tracked diff surfaced as a Review pill in prior captures.

**Missing for daily use:** “Review +X −Y”, PR hint, 3-file cap — not exercised.

---

## §5.8 — Fake-control removal (#129) — FAIL (mic)

### Microphone on composer pill

**Cross-session visual (L1 baseline, re-analyzed this session):**

```bash
python3 -c "
from PIL import Image
import numpy as np
for name in ['L1-00-relaunch','L3-01-workspaces-home']:
    p=f'docs/test-runs/2026-07-16-daily-use-audit/screenshots/{name}.png'
    im=Image.open(p); w,h=im.size
    sub=np.array(im.crop((0,int(h*0.88),w,h)).convert('RGB'))
    ink=(sub[:, int(sub.shape[1]*0.82):].mean(axis=2)<200).sum()
    print(name, 'bottom_right_ink', ink)
"
# L1-00-relaunch bottom_right_ink 712
# L3-01-workspaces-home bottom_right_ink 0   # blank screenshot — inconclusive
```

`screenshots/L1-00-relaunch.png` (L1) shows composer pill with **right-edge glyph** (orchestrator noted microphone icon). This session’s only painted Workspaces capture: `L3-04-workspaces-composer-crop.png` from `L3-01b`.

**Tip source (build under test, not a runtime probe):**

```text
.worktrees/daily-use-audit-2026-07-16/Packages/LancerKit/Sources/AppFeature/Composer/NewChatComposerView.swift:380
    Image(systemName: trimmedDraft.isEmpty ? "mic.fill" : "arrow.up")
```

**Verdict:** **FAIL** vs §5.8 / #129 — non-functional **mic** still ships when draft is empty.

**Missing for daily use:** False affordance on primary compose action; undermines trust on MVP piece 4.

### Profile Help → GitHub

Not tapped. **N-A** this session.

---

## §5.10 — Empty / loading / error honesty (#133) — PARTIAL

**Observed (connected, post-pair):** Workspaces a11y listed `All Repos, 50`, `command-center, 30`, `Home, 20`, `Add Repo` — not the L1-era “0 repos / Checking for agents” empty shell.

**Not exercised:** Airplane mode, failed fetch retry banner, daemon-kill refresh (avoided permanent daemon damage; sim hung before forced error).

**Missing for daily use:** Distinct empty vs loading vs error states not proven under failure.

---

## §5.11 — Thread-list filters (#134) — BLOCKED

Status / Source / Customize sheets not reached — depends on §5.2 thread list (blocked).

---

## Mic-icon finding (summary)

| Source | Finding |
|--------|---------|
| `L1-00-relaunch.png` | Right-edge icon on collapsed composer pill (L1 session; pixel ink 712 in bottom-right crop this session). |
| Tip `NewChatComposerView.swift:380` | `mic.fill` when draft empty. |
| §5.8 plan expectation | No microphone on composer pills. |
| **Result** | **FAIL #129** |

---

## Screenshot index (this lane)

| File | Use |
|------|-----|
| `screenshots/L3-00-onboarding-attempt.png` | Onboarding attempt (blank / early) |
| `screenshots/L3-01-workspaces-home.png` | Early relaunch (blank / early) |
| `screenshots/L3-01b-workspaces-clean.png` | Workspaces with repo rows (painted) |
| `screenshots/L3-02-composer-morph-open.png` | After composer tap |
| `screenshots/L3-02b-composer-morph-closed.png` | After dismiss tap (identical to open) |
| `screenshots/L3-04-workspaces-composer-crop.png` | Composer chrome crop |
| `screenshots/L3-04-workspaces-composer-thumb.png` | Downscaled Workspaces reference |
| `screenshots/L1-00-relaunch.png` | Mic baseline (L1; cited for #129 only) |

---

## Blockers

1. **~05:58 EDT:** `xcrun simctl terminate`, `xcrun simctl io screenshot`, and `idb ui describe-all` against UDID `095F8B3A…` **stopped returning** (commands hung >90s). Blocked §5.2, §5.3 deep-link, §5.11, and offline §5.10.
2. **Early screenshots:** `L3-00` / `L3-01` taken before paint (~99.8% white) — timing, not product blank screen (a11y contradicted white frames).
3. **Onboarding:** No uninstall path without pairing risk.

---

## Verification template

| Gate | Command / artifact | This session |
|------|-------------------|--------------|
| Sim booted | `xcrun simctl list devices booted` | PASS |
| App installed | `/tmp/daily-use-audit-dd/.../Lancer.app` | PASS (L1) |
| Pair intact | plist `583514` confirmed | PASS |
| §2 onboarding | Welcome UI | N-A |
| §5.1 morph | In-place expand, no sheet | FAIL (partial) |
| §5.2 rows | Thread list metadata | BLOCKED |
| §5.3 review | Review sheet | N-A |
| §5.8 mic | No mic on pill | **FAIL** |
| §5.10 honesty | Distinct empty/load/error | PARTIAL |
| §5.11 filters | Status/Source/Customize | BLOCKED |
| Evidence file | `L3-shell-chrome.md` | PASS |

**Evidence clause:** Claims above are limited to commands and artifacts from this session plus explicit L1 screenshot cite for mic baseline; no unverified subagent or doc claims.
