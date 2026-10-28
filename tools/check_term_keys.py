#!/usr/bin/env python3
"""Guard for learners' saved progress.

Progress is saved under a term's permanent key ("nonverb:usta", "verb:yormak"). A built-in term's key is its
"k" field when it has one, otherwise kind:word. Changing the Turkish spelling of a built-in term must therefore
keep the old key by adding "k" to its row, or learners lose that word's history.

tools/term_keys.json holds every key that has ever been in use. This script fails if one of them no longer
resolves to a built-in term (unless it is listed under "moved_to_personal", i.e. now stored per learner in the
database). New keys are added with:  python3 tools/check_term_keys.py --update
"""
import json, re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "app" / "turkish-verb-drill.html"
SNAP = ROOT / "tools" / "term_keys.json"


def current_keys():
    keys = set()
    for line in APP.read_text(encoding="utf-8").splitlines():
        line = line.strip().rstrip(",")
        if line.startswith('{"tr":'):
            row = json.loads(line)
            if row.get("unit") == "bible":
                continue          # stored per learner now (see supabase/migrations)
            keys.add(row.get("k") or "nonverb:" + row["tr"])
        elif line.startswith('{"inf":'):
            row = json.loads(line)
            if row.get("page") == "bible":
                continue
            keys.add(row.get("k") or "verb:" + row["inf"])
    return keys


def main():
    now = current_keys()
    snap = json.loads(SNAP.read_text(encoding="utf-8")) if SNAP.exists() else {"keys": [], "moved_to_personal": []}
    known, moved = set(snap["keys"]), set(snap.get("moved_to_personal", []))
    if "--update" in sys.argv:
        snap["keys"] = sorted(known | now)
        SNAP.write_text(json.dumps(snap, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(f"term_keys.json: {len(snap['keys'])} keys ({len(now - known)} new)")
        return 0
    lost = sorted(k for k in known - now - moved)
    if lost:
        print("These saved-progress keys no longer match any built-in term:")
        for k in lost[:40]:
            print("  ", k)
        print("If a Turkish spelling was changed, add \"k\":\"<old key>\" to that row so learners keep their progress.")
        return 1
    print(f"term keys ok ({len(now)} built-in, {len(known)} remembered)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
