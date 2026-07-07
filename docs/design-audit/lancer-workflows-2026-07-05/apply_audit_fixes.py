#!/usr/bin/env python3
"""Apply 4-pass audit fixes to Lancer workflow HTML artifacts."""

from __future__ import annotations

import re
import shutil
from pathlib import Path

ARTIFACTS = Path("/Users/roshansilva/Downloads/lancer-design-audit-2026-07-05/artifacts")
SCRATCHPAD = Path(
    "/private/tmp/claude-501/-Users-roshansilva-Documents-command-center--claude-worktrees-amazing-mayer-246fef/"
    "e2731d76-081d-45b5-8eda-6d2e2d290171/scratchpad"
)

# Map numbered artifacts to scratchpad names
SCRATCH_MAP = {
    "01-onboarding.html": "workflow-onboarding.html",
    "02-home.html": "workflow-home.html",
    "03-workspaces.html": "workflow-workspaces.html",
    "04-launch-setup.html": "workflow-launch-setup.html",
    "05-work-thread.html": "workflow-thread.html",
    "06-review-diff.html": "workflow-review-diff.html",
    "07-fast-follows.html": "workflow-fast-follows.html",
    "08-ship-history.html": "workflow-ship-history.html",
    "09-platform-gaps.html": "workflow-platform-gaps.html",
    "10-settings.html": "workflow-settings.html",
}

VIEW_ANNOTATIONS_NOTE = (
    " <em>(The <code>.appEntityIdentifier</code> modifier shipped in iOS 18.4; "
    "what's new in WWDC26 is Apple's Siri integration guidance around View Annotations.)</em>"
)

WIDGET_CORRECTION = (
    'Earlier research called this a "full-screen widget" &mdash; that framing doesn\'t hold up. '
    "The real capability is <code>.systemExtraLargePortrait</code> (larger portrait widget family ported from visionOS), "
    "still placed like any Home Screen widget, not a Lock-Screen-covering surface."
)


def patch_file(path: Path, patches: list[tuple[str, str]]) -> int:
    text = path.read_text(encoding="utf-8")
    original = text
    for old, new in patches:
        if old not in text:
            continue
        text = text.replace(old, new, 1)
    if text != original:
        path.write_text(text, encoding="utf-8")
        return 1
    return 0


def apply_onboarding(text: str) -> str:
    # Thesis
    text = text.replace(
        "One product proof, code-only pairing, then account, policy, and notifications &mdash; in that order. The phone earns trust before it asks for any.",
        "One product proof, code-only pairing, then notifications, policy defaults, and an optional account &mdash; in that order. The phone earns trust before it asks for anything non-essential.",
    )
    # Panel A CLI context
    text = text.replace(
        '<div class="onboarding-card">\n                  <div class="review-title" style="font-size:19px;">Steer AI coding agents from your phone.</div>\n                  <p class="review-copy">Review risky actions and keep work moving without opening a laptop.</p>\n                </div>',
        '<div class="onboarding-card">\n                  <div class="review-title" style="font-size:19px;">Steer AI coding agents from your phone.</div>\n                  <p class="review-copy">Lancer connects to the coding-agent CLIs already running on your computer. Review risky actions and keep work moving without opening a laptop.</p>\n                </div>',
    )
    # Swap C (account) and E (notifications) phone slots — extract blocks by regex
    c_pat = re.compile(
        r'(<div class="phone-slot">\s*<p class="slot-label">)C &middot; Account choice(</p>.*?</div>\s*</div>\s*</div>\s*)',
        re.DOTALL,
    )
    e_pat = re.compile(
        r'(<div class="phone-slot">\s*<p class="slot-label">)E &middot; Notifications recovery(</p>.*?</div>\s*</div>\s*</div>\s*)',
        re.DOTALL,
    )
    c_match = c_pat.search(text)
    e_match = e_pat.search(text)
    if c_match and e_match:
        c_block = c_match.group(0)
        e_block = e_match.group(0)
        # Build new C = notifications (pre-prompt, not just recovery)
        new_c = e_block.replace("E &middot; Notifications recovery", "C &middot; Notifications")
        new_c = new_c.replace(
            '<div class="review-title">Get approval alerts.</div>\n                <p class="review-copy">Lancer only interrupts when an agent needs a decision or proof fails.</p>\n                <div class="health-line"><strong>Notifications are off</strong>',
            '<div class="review-title">Know when an agent needs you.</div>\n                <p class="review-copy">Example: &ldquo;Approval waiting on hermes-box &mdash; high-risk patch.&rdquo; Turn on alerts so the first real decision reaches you.</p>\n                <div class="health-line" style="display:none;"><strong>Notifications are off</strong>',
        )
        new_c = new_c.replace(
            '<div class="decision-bar" style="bottom:18px;"><div class="decision">Later</div><div class="decision primary">Open Settings</div></div>',
            '<div class="decision-bar" style="bottom:18px;"><div class="decision">Maybe later</div><div class="decision primary">Turn on</div></div>',
        )
        # Build new E = account skippable
        new_e = c_block.replace("C &middot; Account choice", "E &middot; Account (optional)")
        new_e = new_e.replace(
            '<div class="review-title">How should Lancer remember you?</div>\n                <p class="review-copy">Use an account for recovery and device management, or keep this phone paired locally.</p>',
            '<div class="review-title">Add a Lancer account?</div>\n                <p class="review-copy">Optional. Local pairing already works. An account helps with recovery and a second device later.</p>',
        )
        new_e = new_e.replace(
            '<div class="workspace-meta" style="text-align:center;margin-top:14px;">I already have an account</div>\n              </div>\n            </div>\n          </div>',
            '<div class="workspace-meta" style="text-align:center;margin-top:14px;">I already have an account</div>\n              </div>\n              <div class="decision-bar" style="bottom:18px;"><div class="decision">Skip for now</div><div class="decision primary">Continue</div></div>\n            </div>\n          </div>',
        )
        # Policy panel D update
        policy_old = """<p class="slot-label">D &middot; Policy defaults</p>
            <div class="phone">
              <div class="iphone-status"><span>8:21</span><span>cell wifi batt</span></div>
              <div class="home-content" style="height:520px;padding-top:58px;">
                <div class="review-title">Choose the starting guardrails.</div>
                <p class="review-copy">You can change this later in Settings. Safety prompts are always available.</p>
                <div class="health-line"><strong>Balanced</strong><span>Ask before risky writes, secrets, network, and destructive actions.</span></div>
                <div class="health-line"><strong>Always ask</strong><span>Pause for every action that changes files or environment.</span></div>
                <div class="health-line"><strong>Fast lane</strong><span>Allow low-risk edits; still stop for high-risk actions.</span></div>
              </div>
              <div class="decision-bar" style="bottom:18px;"><div class="decision primary" style="grid-column:1 / -1;">Continue</div></div>
            </div>"""
        policy_new = """<p class="slot-label">D &middot; Policy defaults</p>
            <div class="phone">
              <div class="iphone-status"><span>8:21</span><span>cell wifi batt</span></div>
              <div class="home-content" style="height:520px;padding-top:58px;">
                <div class="review-title">Starting guardrails</div>
                <p class="review-copy"><strong>Balanced</strong> is recommended: ask before risky writes, secrets, network, and destructive actions. Customize anytime in Settings.</p>
                <div class="health-line" style="border-color:rgba(69,189,130,.45);background:rgba(69,189,130,.08);"><strong>Balanced (recommended)</strong><span>Pre-selected. Safety prompts always available regardless of preset.</span></div>
                <div class="workspace-meta" style="text-align:center;margin-top:14px;">Customize presets&hellip;</div>
              </div>
              <div class="decision-bar" style="bottom:18px;"><div class="decision">Customize</div><div class="decision primary">Continue with recommended</div></div>
            </div>"""
        text = text.replace(c_block, "___PLACEHOLDER_C___")
        text = text.replace(e_block, "___PLACEHOLDER_E___")
        text = text.replace(policy_old, policy_new)
        text = text.replace("___PLACEHOLDER_C___", new_c)
        text = text.replace("___PLACEHOLDER_E___", new_e)

    # Flow steps reorder text
    flow_swaps = [
        ("<h3>Account, after pairing succeeds</h3>\n          <p>Two calm cards",
         "<h3>Notifications, right after pairing</h3>\n          <p>Asked immediately after the machine relationship works &mdash; mechanism-critical, not an engagement nicety. Concrete example copy plus Turn on / Maybe later."),
        ("<h3>Pick a guardrail preset</h3>\n          <p>Balanced, Always ask, or Fast lane",
         "<h3>Policy defaults, one tap</h3>\n          <p><strong>Balanced</strong> pre-selected with Continue with recommended; Customize opens the three presets (Balanced, Always ask, Fast lane"),
        ("<h3>Notifications, with a real denied path</h3>\n          <p>A pre-prompt explains why alerts matter before the system sheet; if denied, a dedicated recovery row deep-links to iOS Settings instead of dead-ending.</p>",
         "<h3>Account, optional and last</h3>\n          <p>Skippable offer after pairing and alerts are understood. Local/self-hosted mode needs no account; recovery and second-device sync are the only reasons to add one now.</p>"),
    ]
    for old, new in flow_swaps:
        text = text.replace(old, new)

    # Mobbin lead citation
    github_cite = """<div class="cite-card">
        <div class="src"><a href="https://mobbin.com/screens/d16fca7b-018c-41a5-83e3-80e63ae2d896" target="_blank" rel="noopener">GitHub device verification</a><span class="lesson">Developer-tool code pairing</span></div>
        <p>6-digit monospaced field, expiry time, resend link &mdash; the lead analogy for panels A/B (software device-link, not consumer hardware).</p>
      </div>
      <div class="cite-card">"""
    if "GitHub device verification" not in text:
        text = text.replace('<div class="cite-grid">\n      <div class="cite-card">', '<div class="cite-grid">\n      ' + github_cite)

    return text


def apply_work_thread(text: str) -> str:
    text = text.replace(
        '<div class="card proof"><div class="card-head">Proof ready</div><div class="artifact-body">Checks passed. 5 parallel lanes completed.</div></div>',
        '<div class="card proof"><div class="card-head">Proof ready &middot; 4 of 4 checks passed</div><div class="artifact-body">Device matrix, visual diff, tests, and replay all green.</div></div>',
    )
    text = text.replace(
        '<div class="file-row"><span>file</span><span>handoff-audit.md</span><span><span class="add" style="color:#12966b;">+47</span></span></div>',
        '<div class="file-row"><span>file</span><span>handoff-audit.md</span><span><span class="add" style="color:#12966b;">+47</span> <span style="color:#6f6f6f;font-size:11px;">blame</span></span></div>',
    )
    text = text.replace(
        """<div class="phone-slot"><p class="slot-label">F &middot; Proof ready, high risk</p><div class="phone dark">
            <div class="iphone-status"><span>10:19</span><span>cell wifi batt</span></div>
            <div class="nav-dark"><div class="circle">&#8592;</div><div class="nav-title">policy/evaluate.go fix</div><div class="circle">&hellip;</div></div>
            <div class="scroll">
              <div class="card proof"><div class="card-head">Proof ready</div><div class="artifact-body">Touches <span class="code">policy/evaluate.go</span> &mdash; risk-scored high.</div></div>
              <div class="file-row"><span>file</span><span>policy/evaluate.go</span><span><span style="color:#12966b;">+35</span></span></div>
            </div>
            <div class="rail"><div class="action">PR</div><div class="action">Ready</div><div class="action" style="border-color:rgba(69,189,130,.42);color:#c8f2d9;">Verify&hellip;</div></div>""",
        """<div class="phone-slot"><p class="slot-label">F &middot; Proof ready, high risk</p><div class="phone dark">
            <div class="iphone-status"><span>10:19</span><span>cell wifi batt</span></div>
            <div class="nav-dark"><div class="circle">&#8592;</div><div class="nav-title">policy/evaluate.go fix</div><div class="circle">&hellip;</div></div>
            <div class="scroll">
              <div class="card proof"><div class="card-head">Proof ready &middot; 3 of 4 checks passed</div><div class="artifact-body">Touches <span class="code">policy/evaluate.go</span> &mdash; risk-scored high. <strong style="color:#d69a3a;">Device matrix: 1 of 4 failed.</strong> Cross-vendor verify required before ship.</div></div>
              <div class="file-row"><span>file</span><span>policy/evaluate.go</span><span><span style="color:#12966b;">+35</span> <span style="color:#6f6f6f;font-size:11px;">blame</span></span></div>
            </div>
            <div class="rail"><div class="action highlight" style="border-color:rgba(69,189,130,.55);color:#c8f2d9;font-weight:700;">Verify&hellip; required</div><div class="action" style="opacity:.45;">PR</div><div class="action" style="opacity:.45;">Ready</div></div>""",
    )
    text = text.replace(
        "A third rail action, <strong>Verify&hellip;</strong>, appears only when the mission's own risk score is high &mdash; optional, not required.",
        "When risk is high, <strong>Verify&hellip;</strong> is the <em>required</em> first action on the ship rail &mdash; PR and Ready stay disabled until a cross-vendor second opinion is accepted (same proportional friction as medium+ approval review).",
    )
    return text


def apply_workspaces(text: str) -> str:
    playbook_row = """                <div class="group">
                  <p class="group-title">Repo setup</p>
                  <div class="workspace-row" style="min-height:52px;">
                    <div class="folder"></div>
                    <div><div class="workspace-name">Playbook</div><div class="workspace-meta">Working dir, proof cmd, protected zones</div></div>
                    <div class="workspace-count"><span>&rsaquo;</span></div>
                  </div>
                </div>
                <div class="group">"""
    if "Playbook" not in text:
        text = text.replace(
            '<div class="group">\n                  <p class="group-title">Run targets</p>',
            playbook_row + '\n                  <p class="group-title">Run targets</p>',
        )
    text = text.replace(
        '<div class="src">Tailscale devices &amp; Termius host list<span class="lesson">Developer-trusted framing</span></div>',
        '<div class="src"><a href="https://mobbin.com/screens/e7b43201-3ade-493f-8672-76efbd8bff8f" target="_blank" rel="noopener">Starlink Network &rarr; Devices</a><span class="lesson">Developer-trusted framing</span></div>',
    )
    if VIEW_ANNOTATIONS_NOTE.strip() not in text and "View Annotations API" in text:
        text = text.replace(
            "Tagging each workspace row lets a spoken reference resolve to the specific repo on screen, not a generic app launch.</p>",
            "Tagging each workspace row lets a spoken reference resolve to the specific repo on screen, not a generic app launch." + VIEW_ANNOTATIONS_NOTE + "</p>",
        )
    return text


def apply_fast_follows(text: str) -> str:
    second_opinion_css = """
  .mock .second-opinion-card {
    border: 1px solid rgba(85, 194, 240, .45);
    background: rgba(85, 194, 240, .08);
    border-radius: 16px;
    padding: 13px;
    margin-bottom: 12px;
  }
  .mock .second-opinion-kicker {
    color: #55c2f0;
    font-size: 11px;
    font-weight: 760;
    letter-spacing: .07em;
    text-transform: uppercase;
    margin-bottom: 8px;
  }
"""
    if "second-opinion-card" not in text:
        text = text.replace("</style>", second_opinion_css + "</style>", 1)
    text = text.replace(
        '<div class="review-card">\n                  <div class="review-kicker">Codex found a concern</div>',
        '<div class="second-opinion-card">\n                  <div class="second-opinion-kicker">Second opinion &middot; Codex found a concern</div>',
    )
    text = text.replace(
        '<div class="dcard proof"><div class="dcard-head">Codex review &middot; no issues found</div>',
        '<div class="dcard proof" style="border-color:rgba(85,194,240,.35);"><div class="dcard-head">Second opinion &middot; Codex &middot; no issues found</div>',
    )
    text = text.replace(
        '<p class="slot-label">F &middot; Time travel / fork / Clips</p>',
        '<p class="slot-label">F &middot; Time travel / fork (inside Flight Recorder)</p>',
    )
    text = text.replace(
        '<div class="nav-dark"><div class="circle">&#8592;</div><div class="nav-title">Fork from event</div>',
        '<div class="nav-dark"><div class="circle">&#8592;</div><div class="nav-title">Flight Recorder &middot; fork</div>',
    )
    if "Ship &amp; History" not in text and "Flight Recorder" in text:
        text = text.replace(
            "Export portable proof or start a new mission from this timestamp.</div></div>",
            "Export portable proof or start a new mission from this timestamp. <em>Same timeline as Ship &amp; History &rarr; Flight Recorder; fork is an action on that recorder, not a separate root.</em></div></div>",
        )
    return text


def apply_ship_history(text: str) -> str:
    old_panel = """<div class="phone-slot"><p class="slot-label">E &middot; Sync, billing, proof share</p><div class="phone">
            <div class="iphone-status"><span>8:21</span><span>cell wifi batt</span></div>
            <div class="home-chrome"><div class="circle">&#8592;</div></div>
            <div class="home-title" style="font-size:21px;">Account</div>
            <div class="home-content" style="height:430px;">
              <div class="health-line" style="border-color:rgba(209,139,43,.45);background:rgba(209,139,43,.08);"><strong>Last synced 4m ago</strong><span>Pull to refresh. Approval state remains host-owned.</span></div>
              <div class="workspace-row" style="min-height:58px;"><span>plan</span><div><div class="workspace-name" style="font-size:16px;">Away Mode Solo</div><div class="workspace-meta">Hosted features only; safety always available</div></div><div class="workspace-count">&rsaquo;</div></div>
              <div class="workspace-row" style="min-height:58px;"><span>share</span><div><div class="workspace-name" style="font-size:16px;">Share proof link</div><div class="workspace-meta">Redacted, view-only, expires</div></div><div class="workspace-count">&rsaquo;</div></div>
              <div class="workspace-row" style="min-height:58px;"><span>export</span><div><div class="workspace-name" style="font-size:16px;">Export audit log</div><div class="workspace-meta">Decisions and proof history</div></div><div class="workspace-count">&rsaquo;</div></div>
            </div>
          </div></div>"""
    new_panel = """<div class="phone-slot"><p class="slot-label">E &middot; Share mission proof</p><div class="phone">
            <div class="iphone-status"><span>8:21</span><span>cell wifi batt</span></div>
            <div class="home-chrome"><div class="circle">&#8592;</div></div>
            <div class="home-title" style="font-size:21px;">Share proof</div>
            <div class="home-content" style="height:430px;">
              <div class="health-line"><strong>Checkout fallback fix</strong><span>PR #142 &middot; proof bundle attached &middot; redacted by default</span></div>
              <div class="workspace-row" style="min-height:58px;"><span>share</span><div><div class="workspace-name" style="font-size:16px;">Share proof link</div><div class="workspace-meta">View-only, expires, no secrets</div></div><div class="workspace-count">&rsaquo;</div></div>
              <div class="workspace-row" style="min-height:58px;"><span>export</span><div><div class="workspace-name" style="font-size:16px;">Export lancer.proof</div><div class="workspace-meta">Portable proof package for this mission</div></div><div class="workspace-count">&rsaquo;</div></div>
              <div class="workspace-meta" style="margin-top:16px;">Account, billing, and audit export live in Settings.</div>
            </div>
          </div></div>"""
    text = text.replace(old_panel, new_panel)
    text = text.replace(
        "<h3>Account, honestly</h3><p>Sync state says <strong>when</strong> it last synced",
        "<h3>Share proof, not account settings</h3><p>Contextual share/export for <em>this mission</em> only. Sync, billing, and audit export stay in Settings &mdash; no duplicate Account screen here.",
    )
    # Work Search + Command Palette note
    if "Command Palette" not in text:
        pass
    note = '<p class="screens-caption" style="margin-top:8px;"><strong>Search note:</strong> Work Search (panel D) is the canonical Search/Recent surface. Command Palette (Platform &amp; Gaps) is quick-jump mode within the same search model, not a second inbox.</p>'
    if "Search note" not in text:
        text = text.replace(
            '<p class="screens-caption">Scroll to see all five',
            note + '\n      <p class="screens-caption">Scroll to see all five',
        )
    return text


def apply_settings(text: str) -> str:
    text = text.replace(
        '<div class="workspace-name">Export audit log</div><div class="workspace-meta">Decisions and proof history</div>',
        '<div class="workspace-name">View policy audit log</div><div class="workspace-meta">Opens Security &amp; Approvals</div>',
    )
    text = text.replace(
        "Confirmed against a fresh Mobbin pass of grouped-list settings screens (Zocdoc, Finimize, NYTimes)",
        'Confirmed against grouped-list settings screens (<a href="https://mobbin.com/screens/f97269c5-1cd0-46c1-abaf-0260e0699847" target="_blank" rel="noopener">NYTimes Settings</a>, MLS)',
    )
    return text


def apply_platform_gaps(text: str) -> str:
    if "systemExtraLargePortrait" not in text:
        text = text.replace(
            "Three named full-screen widgets plus fleet-wide status collapse into one template with four data states.",
            WIDGET_CORRECTION + " Three widget ideas collapse into one template with four data states.",
        )
        text = text.replace(
            '3 separate full-screen-widget ideas',
            '3 separate large-portrait widget ideas (<code>.systemExtraLargePortrait</code>)',
        )
    text = text.replace(
        "Docker Compose service health surfaced as an Away Status timeline",
        "Docker Compose service health surfaced under Workspace Detail (repo-scoped, not Home)",
    )
    if "Work Thread" not in text and "git blame" in text.lower():
        text = text.replace(
            "a depth-of-review gap inside Changed Files, not a new screen.",
            "a depth-of-review gap inside Changed Files (see Work Thread panel C file-row blame affordance), not a new root screen.",
        )
    # Command palette note
    if "Work Search is the canonical" not in text:
        text = text.replace(
            "distinct from Work Search",
            "quick-jump mode within Work Search (canonical Search/Recent surface), not a separate inbox",
        )
    return text


def apply_review_diff(text: str) -> str:
    if "mobbin.com/screens/6834fa59" not in text:
        text = text.replace(
            "Closest analog, not copied",
            '<a href="https://mobbin.com/screens/6834fa59-ee3a-4969-a6cc-c27bb0c9ad56" target="_blank" rel="noopener">Manus diff view</a> &middot; closest analog, not copied',
        )
    if VIEW_ANNOTATIONS_NOTE.strip() not in text and "View Annotations API" in text:
        text = text.replace(
            "resolve to the specific changed file on screen, not a generic app launch.</p>",
            "resolve to the specific changed file on screen, not a generic app launch." + VIEW_ANNOTATIONS_NOTE + "</p>",
        )
    return text


def apply_home(text: str) -> str:
    if VIEW_ANNOTATIONS_NOTE.strip() not in text and "View Annotations API" in text:
        text = text.replace(
            "resolve to the specific ledger row on screen, not a generic app launch.</p>",
            "resolve to the specific ledger row on screen, not a generic app launch." + VIEW_ANNOTATIONS_NOTE + "</p>",
        )
    return text


def process_artifact(name: str) -> None:
    path = ARTIFACTS / name
    if not path.exists():
        print(f"SKIP missing {name}")
        return
    text = path.read_text(encoding="utf-8")
    if name.endswith("01-onboarding.html"):
        text = apply_onboarding(text)
    elif name.endswith("05-work-thread.html"):
        text = apply_work_thread(text)
    elif name.endswith("03-workspaces.html"):
        text = apply_workspaces(text)
    elif name.endswith("07-fast-follows.html"):
        text = apply_fast_follows(text)
    elif name.endswith("08-ship-history.html"):
        text = apply_ship_history(text)
    elif name.endswith("10-settings.html"):
        text = apply_settings(text)
    elif name.endswith("09-platform-gaps.html"):
        text = apply_platform_gaps(text)
    elif name.endswith("06-review-diff.html"):
        text = apply_review_diff(text)
    elif name.endswith("02-home.html"):
        text = apply_home(text)
    path.write_text(text, encoding="utf-8")
    print(f"Patched {name}")
    scratch_name = SCRATCH_MAP.get(name)
    if scratch_name and SCRATCHPAD.exists():
        dest = SCRATCHPAD / scratch_name
        shutil.copy2(path, dest)
        print(f"  -> scratchpad {scratch_name}")


def rebuild_combined() -> None:
    """Rebuild 11-combined from individual workflow sections."""
    combined_path = ARTIFACTS / "11-combined-all-workflows.html"
    # Read header/nav from existing combined (first ~200 lines until first workflow)
    existing = combined_path.read_text(encoding="utf-8")
    nav_match = re.search(r"(<nav class=\"jump-nav\">.*?</nav>)", existing, re.DOTALL)
    style_match = re.search(r"(<style>.*?</style>)", existing, re.DOTALL)
    if not style_match:
        print("WARN: could not extract combined styles")
        return

    header = """<title>Lancer Workflows — Complete Set (audit-applied)</title>\n"""
    header += style_match.group(1) + "\n"
    if nav_match:
        header += nav_match.group(1) + "\n"
    header += '<div class="wrap combined">\n'

    workflow_files = [
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

    body_parts = [header]
    ia_note = """
<section class="col" id="ia-fast-follows-note">
  <p class="section-eyebrow">IA note</p>
  <h2>Fast Follows reachability</h2>
  <p>Fast Follows surfaces (Verify with&hellip;, run comparison, regression watch, platform widgets) enter from a finished Work Thread result or proof rail &mdash; contextual, not sidebar roots. Same rule as Review/Diff.</p>
</section>
"""
    for fname, title in workflow_files:
        content = (ARTIFACTS / fname).read_text(encoding="utf-8")
        # Extract from <div class="wrap"> inner content
        m = re.search(r'<div class="wrap">(.*)</div>\s*$', content, re.DOTALL)
        if m:
            inner = m.group(1)
            body_parts.append(f'<section class="workflow-embed" id="wf-{fname[:2]}">\n')
            body_parts.append(f'<h2 class="workflow-divider">{title}</h2>\n')
            body_parts.append(inner)
            body_parts.append("</section>\n")
    body_parts.append(ia_note)
    body_parts.append("</div>\n</body></html>\n")

    combined_path.write_text("".join(body_parts), encoding="utf-8")
    print("Rebuilt 11-combined-all-workflows.html")


def main() -> None:
    for i in range(1, 11):
        process_artifact(f"{i:02d}-" + [
            "onboarding", "home", "workspaces", "launch-setup", "work-thread",
            "review-diff", "fast-follows", "ship-history", "platform-gaps", "settings",
        ][i - 1] + ".html")

    # Apply same global replacements to 11-combined if exists (patch in place for sections)
    combined = ARTIFACTS / "11-combined-all-workflows.html"
    if combined.exists():
        text = combined.read_text(encoding="utf-8")
        for fn in [apply_onboarding, apply_work_thread, apply_workspaces, apply_fast_follows,
                   apply_ship_history, apply_settings, apply_platform_gaps, apply_review_diff, apply_home]:
            text = fn(text)
        combined.write_text(text, encoding="utf-8")
        print("Patched 11-combined in place")

    rebuild_combined()
    print("Done apply script")


if __name__ == "__main__":
    main()
