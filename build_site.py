#!/usr/bin/env python3
"""Build the website into _site/ from app/turkish-verb-drill.html and web/.

GitHub Actions runs this on every push to main and publishes _site/ to
https://jsmethurst.github.io/turkce/ (see .github/workflows/pages.yml).
Run it locally to preview:  python3 build_site.py  then open _site/index.html
through a local web server (e.g. python3 -m http.server -d _site).
"""
import hashlib
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "_site"
SUPABASE_JS = "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.117.2/dist/umd/supabase.js"

src = (ROOT / "app" / "turkish-verb-drill.html").read_text(encoding="utf-8")
# Changes whenever backend.js changes, so browsers don't keep a stale cached copy.
BACKEND_VERSION = hashlib.sha1((ROOT / "web" / "backend.js").read_bytes()).hexdigest()[:8]

src, n = re.subn(r"<title>.*?</title>", "<title>Türkçe</title>", src, count=1)
assert n == 1, "no <title> found"
head_extra = (
    '<meta name="description" content="Turkish verb forms, vocabulary flashcards and a searchable Sözlük.">\n'
    '<link rel="icon" href="favicon.svg" type="image/svg+xml">\n'
    '<link rel="icon" href="favicon-32.png" sizes="32x32" type="image/png">\n'
    '<link rel="apple-touch-icon" href="apple-touch-icon.jpg">\n'
    '<meta name="theme-color" content="#12414D">\n'
    f'<script src="{SUPABASE_JS}"></script>\n'
    f'<script src="backend.js?v={BACKEND_VERSION}"></script>\n'
)
src, n = re.subn(r"(<title>Türkçe</title>\n)", lambda m: m.group(1) + head_extra, src, count=1)
assert n == 1
if not src.lstrip().lower().startswith("<!doctype"):
    src = "<!DOCTYPE html>\n" + src

if OUT.exists():
    shutil.rmtree(OUT)
shutil.copytree(ROOT / "web", OUT)
(OUT / "index.html").write_text(src, encoding="utf-8")
(OUT / ".nojekyll").touch()
print(f"built {OUT.name}/ (index.html {len(src.encode('utf-8')):,} bytes)")
