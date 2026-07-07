#!/usr/bin/env python3
import json
import os
import re
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

PROJECT_PATH = "/Users/kometaninaoki/Documents/life_game_app"
LOG_DIR = "/Users/kometaninaoki/Library/CloudStorage/GoogleDrive-n.kometani@re-startlaw.com/マイドライブ/Obsidian Vault - life_game_app/40_chatlog"
JST = timezone(timedelta(hours=9))

SYSTEM_REMINDER_RE = re.compile(r"<system-reminder>.*?</system-reminder>", re.DOTALL)


def clean_text(text: str) -> str:
    return SYSTEM_REMINDER_RE.sub("", text).strip()


def extract_text_from_content(content) -> str:
    if isinstance(content, str):
        return clean_text(content)
    if isinstance(content, list):
        parts = []
        for p in content:
            if isinstance(p, dict) and p.get("type") == "text":
                parts.append(p.get("text", ""))
        return clean_text("\n".join(parts))
    return ""


def parse_ts(ts_str: str):
    try:
        return datetime.fromisoformat(ts_str.replace("Z", "+00:00")).astimezone(JST)
    except Exception:
        return None


def main():
    try:
        hook_input = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    cwd = hook_input.get("cwd", "")
    if cwd != PROJECT_PATH:
        sys.exit(0)

    transcript_path = hook_input.get("transcript_path")
    session_id = hook_input.get("session_id", "unknown")

    if not transcript_path or not os.path.isfile(transcript_path):
        sys.exit(0)

    entries = []
    try:
        with open(transcript_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entries.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    except Exception as e:
        print(f"chatlog: failed to read transcript: {e}", file=sys.stderr)
        sys.exit(0)

    messages = []
    first_dt = None
    for e in entries:
        etype = e.get("type")
        if etype not in ("user", "assistant"):
            continue
        msg = e.get("message")
        if not isinstance(msg, dict):
            continue
        text = extract_text_from_content(msg.get("content"))
        if not text:
            continue
        ts = parse_ts(e.get("timestamp", ""))
        if first_dt is None and etype == "user" and ts:
            first_dt = ts
        messages.append((etype, ts, text))

    if not messages:
        sys.exit(0)

    if first_dt is None:
        first_dt = datetime.now(JST)

    short_id = session_id[:8] if session_id else "unknown"
    fname = f"{first_dt.strftime('%y%m%d_%H%M')}_{short_id}.md"

    out_lines = [f"# Chat Log — {first_dt.strftime('%Y-%m-%d %H:%M')} JST ({session_id})", ""]
    for role, ts, text in messages:
        label = "User" if role == "user" else "Assistant"
        ts_str = ts.strftime("%Y-%m-%d %H:%M:%S JST") if ts else "(no timestamp)"
        out_lines.append(f"## {label} — {ts_str}")
        out_lines.append("")
        out_lines.append(text)
        out_lines.append("")

    try:
        Path(LOG_DIR).mkdir(parents=True, exist_ok=True)
        out_path = os.path.join(LOG_DIR, fname)
        with open(out_path, "w", encoding="utf-8") as f:
            f.write("\n".join(out_lines))
    except Exception as e:
        print(f"chatlog: failed to write log: {e}", file=sys.stderr)
        sys.exit(0)

    sys.exit(0)


if __name__ == "__main__":
    main()
