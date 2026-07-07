#!/usr/bin/env python3
"""Rebuild 11-combined-all-workflows.html from individual workflow artifacts."""

from __future__ import annotations

import re
from pathlib import Path

ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

WORKFLOW_FILES = [
    ("01-onboarding.html", "01 — Onboarding"),
    ("02-home.html", "02 — Home"),
    ("03-workspaces.html", "03 — Workspaces"),
    ("04-launch-setup.html", "04 — Launch Setup"),
    ("05-work-thread.html", "05 — Work Thread"),
    ("06-review-diff.html", "06 — Review & Diff"),
    ("07-fast-follows.html", "07 — Fast Follows"),
    ("08-ship-history.html", "08 — Ship & History"),
    ("09-platform-gaps.html", "09 — Platform & Gaps"),
    ("10-settings.html", "10 — Settings"),
]

IA_NOTE = """
<section class="col" id="ia-fast-follows-note">
  <p class="section-eyebrow">IA note</p>
  <h2>Fast Follows &amp; governance reachability</h2>
  <p>Fast Follows surfaces (Verify with&hellip;, vendor performance, continuous cross-vendor audit) enter from a finished Work Thread result or Settings &rarr; Security. Policy Diff Review, cross-host policy check, on-device audit digest, account switcher, and compliance export live under Settings and Workspaces &mdash; contextual, not sidebar roots.</p>
</section>
"""


def main() -> None:
    combined_path = ARTIFACTS / "11-combined-all-workflows.html"
    existing = combined_path.read_text(encoding="utf-8")
    nav_match = re.search(r"(<nav class=\"jump-nav\">.*?</nav>)", existing, re.DOTALL)
    style_match = re.search(r"(<style>.*?</style>)", existing, re.DOTALL)
    if not style_match:
        raise SystemExit("Could not extract combined styles")

    parts = [
        "<title>Lancer Workflows — Complete Set (audit-applied + phantom features)</title>\n",
        style_match.group(1) + "\n",
    ]
    if nav_match:
        parts.append(nav_match.group(1) + "\n")
    parts.append('<div class="wrap combined">\n')

    for fname, title in WORKFLOW_FILES:
        content = (ARTIFACTS / fname).read_text(encoding="utf-8")
        m = re.search(r'<div class="wrap">(.*)</div>\s*$', content, re.DOTALL)
        if not m:
            raise SystemExit(f"Could not extract wrap content from {fname}")
        parts.append(f'<section class="workflow-embed" id="wf-{fname[:2]}">\n')
        parts.append(f'<h2 class="workflow-divider">{title}</h2>\n')
        parts.append(m.group(1))
        parts.append("</section>\n")

    parts.append(IA_NOTE)
    parts.append("</div>\n</body></html>\n")
    combined_path.write_text("".join(parts), encoding="utf-8")
    print(f"Rebuilt {combined_path}")


if __name__ == "__main__":
    main()
