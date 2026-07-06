#!/usr/bin/env python3
"""Remove stale doc citations from lancer-workflows wireframe HTML + companion markdown."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "docs" / "design-audit" / "lancer-workflows-2026-07-05"

INLINE_NOTE = (
    "Platform notes are curated inline below "
    "(WWDC 2026 research source purged 2026-07-06)."
)

FULL_SOURCE_RE = re.compile(
    r'<p class="col" style="color:var\(--muted\);font-size:14px;margin-top:6px;">'
    r"Full source doc: <span class=\"mono\">docs/design-audit/2026-07-05-ios27-wwdc26-platform-capabilities\.md</span>"
    r"[^<]*</p>",
    re.DOTALL,
)

PILL_REPLACEMENTS = [
    (re.compile(r"<span class=\"pill source\">lancer-core-wireframes-2026-07-05/index\.html#[^<]+</span>\s*"), ""),
    (re.compile(r"<span class=\"pill source\">workflows/[^<]+\.md</span>\s*"), ""),
]

FOOTER_REMOVALS = [
    "docs/design-audit/2026-07-05-ios27-wwdc26-platform-capabilities.md",
    "docs/design-audit/lancer-core-wireframes-2026-07-05/",
    "docs/design-audit/workflows/",
]

CANONICAL_FOOTER = "docs/design-audit/lancer-workflows-2026-07-05/MASTER-REPORT.md"


def clean_html(text: str) -> str:
    text = FULL_SOURCE_RE.sub(
        f'<p class="col" style="color:var(--muted);font-size:14px;margin-top:6px;">{INLINE_NOTE}</p>',
        text,
    )
    for pattern, repl in PILL_REPLACEMENTS:
        text = pattern.sub(repl, text)
    lines = text.splitlines()
    out: list[str] = []
    for line in lines:
        if any(bad in line for bad in FOOTER_REMOVALS):
            continue
        out.append(line)
    text = "\n".join(out)
    if CANONICAL_FOOTER not in text and "<footer>" in text:
        text = text.replace(
            "  <footer>\n    <p>Sources for this page</p>\n    <div class=\"files\">",
            "  <footer>\n    <p>Sources for this page</p>\n    <div class=\"files\">\n"
            f"      <span>{CANONICAL_FOOTER}</span>",
            1,
        )
    return text


def clean_markdown(text: str) -> str:
    text = text.replace(
        "`docs/design-audit/2026-07-05-ios27-wwdc26-platform-capabilities.md`",
        "inline WWDC 2026 platform notes in each artifact (source research purged 2026-07-06)",
    )
    text = text.replace(
        "- `2026-07-05-ios27-wwdc26-platform-capabilities.md` — iOS 27 / WWDC 2026 research\n",
        "",
    )
    text = text.replace(
        "`docs/product/2026-07-05-mobile-native-ai-coding-workflow-research.md`",
        "`docs/product/2026-07-05-lancer-feature-master-plan.md` §3",
    )
    return text


def main() -> None:
    if not ROOT.exists():
        raise SystemExit(f"missing wireframe bundle: {ROOT}")

    changed: list[str] = []
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file():
            continue
        if path.suffix not in {".html", ".md"}:
            continue
        original = path.read_text(encoding="utf-8")
        updated = clean_markdown(original) if path.suffix == ".md" else clean_html(original)
        if updated != original:
            path.write_text(updated, encoding="utf-8")
            changed.append(str(path.relative_to(ROOT.parents[1])))

    print(f"updated {len(changed)} files")
    for item in changed:
        print(f"  - {item}")


if __name__ == "__main__":
    main()
