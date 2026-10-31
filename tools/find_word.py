#!/usr/bin/env python3
"""Is this Turkish word already there?  python3 tools/find_word.py kitap "tamir etmek" ...

Looks across the uneditable lists (A1 / A2, i.e. the DICTIONARY in the page) AND Jacob's Personal lists
(tools/jacob_personal.json) and says where each word lives. Run it before adding any word to either place.
Spelling is compared the Turkish way (İ/ı, Ş, Ç, Ğ, Ö, Ü are not folded), ignoring case only.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_sozluk import load_dictionary, PERSONAL  # noqa: E402


def low(s):
    return s.replace("I", "ı").replace("İ", "i").lower().strip()


def main(words):
    d = load_dictionary()
    index = {}
    unit = {1: "1. Ünite", 2: "2. Ünite", "other": "Derste", "sifatlar": "Sıfatlar"}
    for v in d["verbs"]:
        where = f"verb, {v['page']}. Sayfa" if isinstance(v["page"], int) else "verb, Derste"
        index.setdefault(low(v["inf"]), []).append(f"{where} ({v['gloss']})")
    for n in d["nonverbs"]:
        index.setdefault(low(n["tr"]), []).append(f"non-verb, {unit.get(n['unit'], n['unit'])} ({n['en']})")
    if PERSONAL.exists():
        for l in json.loads(PERSONAL.read_text(encoding="utf-8"))["lists"]:
            for tr, en in l["terms"]:
                index.setdefault(low(tr), []).append("Jacob's personal " + l["kind"] + ' list "' + l["name"] + '" (' + en + ")")
    for w in words:
        hits = index.get(low(w))
        print(f"{w}: " + ("not found" if not hits else "; ".join(hits)))


if __name__ == "__main__":
    main(sys.argv[1:] or ["usta"])
