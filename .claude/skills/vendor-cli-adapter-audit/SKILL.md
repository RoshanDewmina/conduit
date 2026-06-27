---
name: vendor-cli-adapter-audit
description: Use when changing, reviewing, or planning Lancer agent adapter behavior for Claude Code, Codex, OpenCode, or Kimi Code, including launch argv, continue/resume argv, JSON streaming schemas, sandbox/permission flags, hooks, policy gates, budget gates, and headless smoke tests.
---

# Vendor CLI Adapter Audit

## Overview

Use this skill before trusting any agent CLI claim. These tools change quickly, and the local installed version can differ from generated reports or web docs.

## Required Checks

1. Read `/Users/roshansilva/.hermes/knowledge-base/AGENTS.md`.
2. Inspect current code in `daemon/lancerd/dispatch.go` before proposing adapter changes.
3. Re-run `which`, local version, and targeted help commands for each affected CLI.
4. Audit four planes separately: launch argv, continue argv, stream parsing, and hook/install/doctor coverage.
5. Check current official docs when the flag, permission model, or resume behavior could have changed.
6. Compare claims in `/Users/roshansilva/Downloads/ai-coding-agents-comprehensive-study.md` against local help and code.
7. Smoke test headless behavior with harmless prompts in a temp directory before shipping a new argv.

## Non-Negotiables

- Build explicit argv arrays. Never use `sh -c` with interpolated prompts.
- Continue/resume must re-pass Lancer policy and budget gates.
- Continue must keep the current identity model unless deliberately changed: Lancer gets a new `runId`, vendor session continuity lives underneath it.
- A hook script existing in `docs/` is not proof that it is installed, trusted, called by the vendor runtime, or checked by doctor/install flows.
- Treat Codex sandbox bypass as unsafe unless the user explicitly opts in and hook/gating coverage is verified.
- Treat Kimi non-interactive permission behavior as high-risk until verified for the installed version.
- Do not add `--yolo`, `--auto`, or `--plan` to Kimi prompt-mode argv unless current local help explicitly permits it.
- Store "current as of" dates with any durable matrix because CLI flags drift.

## Reference

Load `references/vendor-cli-matrix.md` for command recipes, known 2026-06-18 baseline findings, and smoke-check patterns.
