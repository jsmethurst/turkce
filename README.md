# Türkçe

Turkish verb forms, vocabulary flashcards and a searchable Sözlük.

Live site: https://jsmethurst.github.io/turkce/

- `app/turkish-verb-drill.html`: the app, including the word list.
- `web/`: Supabase sign-in and sync (`backend.js`) plus the icons.
- `build_site.py`: builds `_site/`. GitHub Actions runs it and publishes on every push to `main`.
- `tools/make_sozluk.py`: regenerates `sozluk.txt` from the word list.

See `CLAUDE.md` for how to add words and make changes.
