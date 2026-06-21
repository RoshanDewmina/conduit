#!/usr/bin/env bash
set -euo pipefail

days="${1:-7}"
repo="${2:-$PWD}"

python3 - "$days" "$repo" <<'PY'
import json
import os
import pathlib
import sqlite3
import sys
import time

try:
    days = int(sys.argv[1])
except Exception:
    days = 7
repo = sys.argv[2]
home = pathlib.Path.home()
cutoff = time.time() - days * 86400

def rel(path):
    try:
        return str(path).replace(str(home), "~", 1)
    except Exception:
        return str(path)

def short(text, limit=140):
    text = " ".join(str(text or "").split())
    return text[: limit - 3] + "..." if len(text) > limit else text

def norm_ts(value):
    try:
        v = float(value)
    except Exception:
        return None
    if v > 10_000_000_000:
        v = v / 1000.0
    return v

def iso(value):
    t = norm_ts(value)
    if not t:
        return ""
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t))

def print_header(name):
    print(f"\n## {name}")

def escaped_cwd(path):
    return path.replace("/", "-").replace(".", "-")

print(f"Recent local agent sessions from the last {days} day(s)")
print(f"Repo anchor: {repo}")

print_header("Claude Code")
claude_dirs = []
primary = home / ".claude" / "projects" / escaped_cwd(repo)
if primary.exists():
    claude_dirs.append(primary)
projects = home / ".claude" / "projects"
if projects.exists():
    for p in sorted(projects.iterdir(), key=lambda x: x.stat().st_mtime if x.exists() else 0, reverse=True)[:8]:
        if p not in claude_dirs and p.is_dir():
            claude_dirs.append(p)
count = 0
for d in claude_dirs:
    for f in sorted(d.glob("*.jsonl"), key=lambda x: x.stat().st_mtime, reverse=True)[:12]:
        if f.stat().st_mtime < cutoff:
            continue
        title = ""
        session_id = ""
        try:
            with f.open("r", encoding="utf-8", errors="replace") as fh:
                for _, line in zip(range(120), fh):
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    session_id = session_id or str(obj.get("sessionId") or obj.get("session_id") or "")
                    if obj.get("summary"):
                        title = obj.get("summary")
                        break
                    msg = obj.get("message")
                    if isinstance(msg, dict) and msg.get("role") == "user":
                        content = msg.get("content")
                        if isinstance(content, str):
                            title = content
                            break
                        if isinstance(content, list) and content:
                            title = content[0].get("text") if isinstance(content[0], dict) else str(content[0])
                            break
        except Exception as exc:
            title = f"read error: {exc}"
        print(f"- {time.strftime('%Y-%m-%d %H:%M', time.localtime(f.stat().st_mtime))} {rel(f)} id={session_id} title={short(title)}")
        count += 1
if count == 0:
    print("- no recent Claude JSONL candidates found")

print_header("Codex")
codex_root = home / ".codex" / "sessions"
codex_titles = {}
codex_index = home / ".codex" / "session_index.jsonl"
if codex_index.exists():
    try:
        with codex_index.open("r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    row = json.loads(line)
                except Exception:
                    continue
                if row.get("id"):
                    codex_titles[str(row.get("id"))] = str(row.get("thread_name") or "")
    except Exception:
        pass
count = 0
if codex_root.exists():
    files = sorted(codex_root.rglob("rollout-*.jsonl"), key=lambda x: x.stat().st_mtime, reverse=True)[:60]
    for f in files:
        if f.stat().st_mtime < cutoff:
            continue
        sid = ""
        cwd = ""
        title = ""
        try:
            with f.open("r", encoding="utf-8", errors="replace") as fh:
                for _, line in zip(range(180), fh):
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    payload = {}
                    if obj.get("type") == "session_meta" and isinstance(obj.get("payload"), dict):
                        payload = obj.get("payload") or {}
                    elif isinstance(obj.get("session_meta"), dict):
                        payload = obj.get("session_meta", {}).get("payload", {}) or {}
                    sid = sid or str(payload.get("id") or "")
                    cwd = cwd or str(payload.get("cwd") or "")
                    if sid and not title:
                        title = codex_titles.get(sid, "")
                    item = obj.get("response_item")
                    if obj.get("type") == "response_item" and isinstance(obj.get("payload"), dict):
                        item = obj.get("payload")
                    if isinstance(item, dict) and not title and item.get("type") == "message" and item.get("role") == "user":
                        content = item.get("content") or item.get("text")
                        if isinstance(content, list):
                            parts = []
                            for part in content:
                                if isinstance(part, dict):
                                    parts.append(str(part.get("text") or part.get("input_text") or ""))
                                else:
                                    parts.append(str(part))
                            content = " ".join(p for p in parts if p)
                        if content:
                            normalized = str(content).lstrip()
                            if not (
                                normalized.startswith("# AGENTS.md instructions")
                                or normalized.startswith("<permissions instructions>")
                                or normalized.startswith("<environment_context>")
                            ):
                                title = content
                    ctx = obj.get("turn_context")
                    if isinstance(ctx, dict) and not cwd:
                        cwd = str(ctx.get("cwd") or "")
        except Exception as exc:
            title = f"read error: {exc}"
        if repo in cwd or not cwd:
            print(f"- {time.strftime('%Y-%m-%d %H:%M', time.localtime(f.stat().st_mtime))} {rel(f)} id={sid} cwd={cwd} hint={short(title)}")
            count += 1
if count == 0:
    print("- no recent Codex rollout candidates found")

print_header("OpenCode")
db = home / ".local" / "share" / "opencode" / "opencode.db"
if db.exists():
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        con.row_factory = sqlite3.Row
        cols = [r[1] for r in con.execute("pragma table_info(session)")]
        order = "time_updated" if "time_updated" in cols else ("updated" if "updated" in cols else ("time_created" if "time_created" in cols else "id"))
        rows = con.execute(f"select * from session order by {order} desc limit 25").fetchall()
        printed = 0
        for row in rows:
            data = dict(row)
            t = norm_ts(data.get("time_updated") or data.get("updated") or data.get("time_created") or data.get("created"))
            if t and t < cutoff:
                continue
            title = data.get("title") or data.get("name") or ""
            directory = data.get("directory") or data.get("cwd") or data.get("path") or ""
            if directory and repo not in str(directory):
                continue
            print(f"- {iso(data.get('time_updated') or data.get('updated') or data.get('time_created') or data.get('created'))} id={data.get('id')} cwd={directory} title={short(title)}")
            printed += 1
        if printed == 0:
            print("- no recent OpenCode DB rows matched the repo anchor")
    except Exception as exc:
        print(f"- could not read OpenCode DB: {exc}")
else:
    print("- OpenCode DB not found")

print_header("Kimi Code")
kimi_root = home / ".kimi-code" / "sessions"
count = 0
if kimi_root.exists():
    states = sorted(kimi_root.rglob("state.json"), key=lambda x: x.stat().st_mtime, reverse=True)[:60]
    for f in states:
        if f.stat().st_mtime < cutoff:
            continue
        try:
            data = json.loads(f.read_text(encoding="utf-8", errors="replace"))
        except Exception as exc:
            data = {"title": f"read error: {exc}"}
        title = data.get("title") or data.get("summary") or ""
        sid = data.get("sessionId") or data.get("session_id") or f.parent.name
        print(f"- {time.strftime('%Y-%m-%d %H:%M', time.localtime(f.stat().st_mtime))} {rel(f)} id={sid} title={short(title)}")
        count += 1
if count == 0:
    print("- no recent Kimi state.json candidates found")
PY
