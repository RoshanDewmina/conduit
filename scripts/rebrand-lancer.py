#!/usr/bin/env python3
"""Conduit -> Lancer text migration. PRESERVES deployed-infra identifiers.

Run from repo root:
  python3 scripts/rebrand-lancer.py --dry-run    # report counts, mutate nothing
  python3 scripts/rebrand-lancer.py --apply      # rewrite files in place

Structural renames (dirs, Go module, pbxproj) are handled separately by the
caller; this only does in-file text substitution.
"""
import os, re, sys, subprocess

# --- Infra identifiers that must NOT change (still deployed under "conduit") ---
# Cloud Run hosts, GCS bucket, GCP project, fly.dev, owned *.conduit.dev domains.
PRESERVE = [
    r"conduit-push-[a-z0-9]+-[a-z0-9]+\.a\.run\.app",
    r"conduit-push-smoke-[a-z0-9]+-[a-z0-9]+\.a\.run\.app",
    r"conduit-dist-[a-f0-9]+",
    r"conduit-runner-[a-z0-9]+",
    r"conduit-my-workspace-[a-z0-9]+",
    r"conduit-push\.fly\.dev(?![a-z])",
    r"[a-z0-9-]+\.conduit\.dev(?![a-z])",   # api./push./relay./www. etc.
    r"conduit\.dev(?![a-z])",               # domain, NOT conduit.device.*
    r"conduitd?\.app(?![a-z])",             # conduit.app / conduitd.app domains
]
PRESERVE_RE = re.compile("|".join(f"(?:{p})" for p in PRESERVE))

# Ordered substitutions applied AFTER infra tokens are masked out.
# lowercase `conduit`->`lancer` also turns conduitd->lancerd (conduit+d).
SUBS = [
    (re.compile(r"Conduit"), "Lancer"),
    (re.compile(r"CONDUIT_"), "LANCER_"),
    (re.compile(r"CONDUIT"), "LANCER"),
    (re.compile(r"conduit"), "lancer"),
]

SKIP_DIRS = {".git", ".build", "DerivedData", "build", "node_modules", ".swiftpm"}
# Binary / non-text extensions to skip.
SKIP_EXT = {".png",".jpg",".jpeg",".gif",".pdf",".ico",".icns",".car",".xcarchive",
            ".zip",".tar",".gz",".mp4",".mov",".ttf",".otf",".woff",".woff2",
            ".storekit",".xcuserstate",".bin",".a",".dylib",".o"}

def mask(text):
    holds = []
    def repl(m):
        holds.append(m.group(0)); return f"\x00{len(holds)-1}\x00"
    return PRESERVE_RE.sub(repl, text), holds

def unmask(text, holds):
    for i, h in enumerate(holds):
        text = text.replace(f"\x00{i}\x00", h)
    return text

def transform(text):
    masked, holds = mask(text)
    for rx, rep in SUBS:
        masked = rx.sub(rep, masked)
    return unmask(masked, holds)

def tracked_files():
    out = subprocess.check_output(["git", "ls-files"], text=True)
    return [f for f in out.splitlines() if f]

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "--dry-run"
    changed = 0; total_repl = 0; sample = []
    for f in tracked_files():
        if any(part in SKIP_DIRS for part in f.split("/")): continue
        _, ext = os.path.splitext(f)
        if ext.lower() in SKIP_EXT: continue
        try:
            with open(f, "r", encoding="utf-8") as fh: src = fh.read()
        except (UnicodeDecodeError, FileNotFoundError, IsADirectoryError):
            continue
        if "onduit" not in src and "CONDUIT" not in src: continue
        dst = transform(src)
        if dst == src: continue
        n = sum(1 for a,b in zip(src,dst) if a!=b)  # rough
        changed += 1
        # count actual replacements
        before = len(re.findall(r"[Cc]onduit|CONDUIT", src))
        after  = len(re.findall(r"[Cc]onduit|CONDUIT", dst))
        total_repl += (before - after)
        if len(sample) < 12: sample.append((f, before-after))
        if mode == "--apply":
            with open(f, "w", encoding="utf-8") as fh: fh.write(dst)
    print(f"files changed: {changed}")
    print(f"approx conduit-tokens replaced: {total_repl}")
    print("sample:")
    for f, n in sample: print(f"  {n:4d}  {f}")
    # Safety: confirm no infra token got mangled in apply mode
    if mode == "--apply":
        leaked = subprocess.run(["grep","-rIl","lancer-push-\\|lancer-dist-\\|lancer-runner-\\|lancer-my-workspace\\|lancer\\.dev\\|lancer-push.fly",
                                 "."], capture_output=True, text=True).stdout
        if leaked.strip():
            print("WARNING: possible infra-token corruption in:\n"+leaked)
        else:
            print("infra-token check: clean")

if __name__ == "__main__":
    main()
