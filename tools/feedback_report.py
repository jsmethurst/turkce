#!/usr/bin/env python3
"""Show "Suggest a change" feedback from the Supabase feedback table in a readable form.

Runs on Jacob's Mac (needs the Supabase CLI, logged in and linked; run from the repo root):
    python3 tools/feedback_report.py           # everything not yet marked handled
    python3 tools/feedback_report.py --done 4 5   # mark #4 and #5 handled

Output is in Jacob's format: a count line, then per suggestion "#N · time", "From:", "Where:",
"Feedback: \"…\"" and, only if there is one, "Screenshot: [path]". When posting to Jacob, print
"Screenshot:" and then send that image file right there (not the path); a blank line separates suggestions.
"""
import base64
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

SUPABASE = "/opt/homebrew/bin/supabase"
SHOT_DIR = Path("/tmp/turkce-feedback")
TZ = ZoneInfo("Europe/Istanbul")


def sql(query):
    out = subprocess.run([SUPABASE, "db", "query", "--linked", query],
                         check=True, capture_output=True, text=True).stdout
    return json.loads(out[out.find("{"):])["rows"]


def device(ua):
    ua = ua or ""
    os_ = ("iPhone" if "iPhone" in ua else "iPad" if "iPad" in ua else "Android" if "Android" in ua
           else "Mac" if "Macintosh" in ua else "Windows" if "Windows" in ua else "Linux" if "Linux" in ua else "Unknown device")
    browser = ("Edge" if "Edg/" in ua else "Firefox" if "Firefox" in ua else "Chrome" if ("Chrome" in ua or "CriOS" in ua)
               else "Safari" if "Safari" in ua else "")
    return f"{os_}, {browser}" if browser else os_


def when(ts):
    t = datetime.fromisoformat(ts.replace(" ", "T").replace("+00", "+00:00")).astimezone(TZ)
    return t.strftime("%a %-d %b, %H:%M")


def main(args):
    if args[:1] == ["--done"]:
        ids = [int(a) for a in args[1:]]
        if ids:
            sql(f"update public.feedback set synced_at = now() where id in ({','.join(map(str, ids))})")
            print("Marked handled: " + ", ".join(f"#{i}" for i in ids))
        return
    rows = sql("select id, created_at, email, context, message, user_agent, screenshot is not null as shot "
               f"from public.feedback where synced_at is null order by id")
    if not rows:
        print("No feedback waiting.")
        return
    SHOT_DIR.mkdir(exist_ok=True)
    print(f"{len(rows)} suggestion{'s' if len(rows) != 1 else ''}\n")
    for r in rows:
        who = r["email"] or "not signed in"
        msg = " ".join((r["message"] or "").split())
        print(f"#{r['id']} · {when(r['created_at'])}")
        print(f"From: {who} · {device(r['user_agent'])}")
        print(f"Where: {r['context'] or '—'}")
        print(f'Feedback: "{msg}"')
        if r["shot"]:
            data = sql(f"select screenshot from public.feedback where id = {int(r['id'])}")[0]["screenshot"]
            m = re.match(r"data:image/(png|jpeg);base64,(.+)", data, re.S)
            if m:
                path = SHOT_DIR / f"feedback-{r['id']}.{'jpg' if m[1] == 'jpeg' else 'png'}"
                path.write_bytes(base64.b64decode(m[2]))
                print(f"Screenshot: [{path}]")
        print()


if __name__ == "__main__":
    main(sys.argv[1:])
