#!/usr/bin/env python3
"""Regenerate sozluk.txt (a plain-text copy of the Sözlük) from the DICTIONARY in app/turkish-verb-drill.html.

Run after any word change:  python3 tools/make_sozluk.py
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "app" / "turkish-verb-drill.html"
OUT = ROOT / "sozluk.txt"
COL = 26
RULE = "=" * 60


def load_dictionary():
    src = APP.read_text(encoding="utf-8")
    start = src.index("const DICTIONARY = {")
    parts = {}
    for name, nxt in (("verbs", "nonverbs"), ("nonverbs", "topics"), ("topics", None)):
        a = src.index(f"\n{name}: [", start) + len(f"\n{name}: ")
        b = src.index(f"\n{nxt}: [", a) if nxt else src.index("\n]", a) + 2
        body = src[a:b].rstrip().rstrip(",")
        parts[name] = json.loads(body)
    for k in parts:
        parts[k].sort(key=lambda r: r["order"])
    return parts


def upper_tr(label):
    # "1. Ünite 26-50" -> "1. ÜNİTE 26-50"; plain .upper() would give "ÜNITE".
    return label.replace("i", "İ").upper() if "Ünite" in label else label.upper()


def section(title):
    return [title, "-" * len(title)]


def verb_lines(v):
    lines = [v["inf"].ljust(COL) + v["gloss"]]
    for c in v.get("cases") or []:
        ex = re.sub(r"</?b>", "", c["ex"])
        lines.append(f"    {c['c']}: {ex}  ({c['en']})")
    return lines


def chunks(items, size=25):
    for i in range(0, len(items), size):
        yield i + 1, i + len(items[i:i + size]), items[i:i + size]


def main():
    d = load_dictionary()
    verbs, nonverbs, topics = d["verbs"], d["nonverbs"], d["topics"]
    out = ["TÜRKÇE — SÖZLÜK", "", f"{len(verbs)} verbs · {len(nonverbs)} non-verbs · {len(topics)} topics", "",
           RULE, "FİİLLER (VERBS)", RULE, ""]
    groups = []
    n = 0
    for page in (1, 2, 3, 4):
        items = [v for v in verbs if v["page"] == page]
        if items:
            groups.append((f"{page}. SAYFA {n + 1}-{n + len(items)}", items))
            n += len(items)
    for page, name in (("other", "DERSTE"), ("bible", "BIBLE")):
        items = [v for v in verbs if v["page"] == page]
        for a, b, chunk in chunks(items):
            groups.append((f"{name} {a}-{b}", chunk))
    for title, items in groups:
        out += section(title)
        for v in items:
            out += verb_lines(v)
        out.append("")
    out += ["", RULE, "NON-VERBS", RULE, ""]
    units = [(1, "1. Ünite"), (2, "2. Ünite"), ("other", "Derste"), ("sifatlar", "Sıfatlar"), ("bible", "Bible")]
    for unit, name in units:
        items = [x for x in nonverbs if x["unit"] == unit]
        for a, b, chunk in chunks(items):
            out += section(upper_tr(f"{name} {a}-{b}"))
            out += [x["tr"].ljust(COL) + x["en"] for x in chunk]
            out.append("")
    out += ["", RULE, "TOPICS", RULE, ""]
    for t in topics:
        out += section(t["label"])
        out += [", ".join(t["terms"]), ""]
    OUT.write_text("\n".join(out).rstrip("\n") + "\n", encoding="utf-8")
    print(f"wrote {OUT.name}: {len(verbs)} verbs, {len(nonverbs)} non-verbs, {len(topics)} topics")


if __name__ == "__main__":
    main()
