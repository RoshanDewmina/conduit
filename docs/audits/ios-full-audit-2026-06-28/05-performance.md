# 05 — Performance

## Approach
Per the plan, **no blanket profiling** — profile only where a finding points, and never claim an
improvement without a before/after measurement. The audit looked for runtime hotspots across the
launch path, SwiftUI body recomputation, list/scroll, networking, persistence, and timers.

## What was found
- **No runtime performance hotspot surfaced.** The launch path, GRDB access, and the block-terminal
  pipeline showed no obvious main-thread stalls or pathological recomputation in code review.
- The only performance signal is **compile-time, not runtime**: `AppRoot.mainBody` takes 380ms to
  type-check (ARCH-1) — a build/IDE-iteration cost, not a user-facing one. Fixing it (view-body
  extraction) improves build time; it is **not** a runtime optimisation and no runtime claim is made.

## Consequently
- **No Instruments run was warranted** (Time Profiler / Allocations / Leaks / Hangs). Spinning them
  up with no candidate bottleneck would produce noise, not signal.
- If Phase B's ARCH-1 extraction is done, the verifiable metric is the **type-check time** of the
  changed property (Xcode build-timing report), measured before/after — not a runtime benchmark.

## Simulator vs device
All observations are static/code-review based. **Any future** runtime, energy, thermal, or GPU
conclusions require a physical device — the simulator is not authoritative for those. None are
claimed here.

## Candidate scenarios for a future, device-based perf pass (not done here)
Cold/warm launch to interactive; block-terminal scroll under a long transcript; repeated
session attach/detach memory growth (relates to CONC-1's task accumulation). Flagged for when a
device + a reproducible scenario are available; out of scope for this static audit.
