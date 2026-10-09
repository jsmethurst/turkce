# Türkçe — Turkish verb & vocabulary drill

Live site: https://jsmethurst.github.io/turkce/ (owner: Jacob, jsmethurst). It's a single-page app with three tabs:
- **Forms:** conjugation drills.
- **Vocab:** flashcards and tests.
- **Sözlük:** the word list, with group and topic chips.

Learners sign in with email and password through Supabase so their progress syncs between devices.

## How publishing works
Every push to `main` triggers `.github/workflows/pages.yml`. It runs `build_site.py`, checks the JavaScript parses, and deploys `_site/` to GitHub Pages. The site is live about a minute after the push.

Browsers may reuse the page for up to 10 minutes. Pages that are already open notice the new build through `version.json`, which `build_site.py` writes, and show a "Türkçe has been updated. Reload" bar. Nobody needs to be told to refresh.

**Always `git pull` before you start.** Jacob works on this repo both from his Mac and from cloud sessions.

**Always commit and push directly to `main`.** Don't create a feature branch or a pull request; this is Jacob's standing instruction, and it's how his changes go live. If the session started on another branch, switch to `main` (`git checkout main && git pull`), make the change there, then `git push origin main`. If the push is rejected because `main` moved, run `git pull --rebase` and push again.

## Files
| Path | What it is |
|---|---|
| `app/turkish-verb-drill.html` | **The app.** The whole UI and logic, plus the built-in word list (`const DICTIONARY = {verbs:[...], nonverbs:[...], topics:[...]}`, one JSON row per line). Edit this file. |
| `web/backend.js` | Supabase sign-in, the account pill and dropdown, and saving each person's data to the `user_docs` table. |
| `web/favicon.svg`, `favicon-32.png`, `apple-touch-icon.jpg` | Logo and icons (a smiling çay glass). The same SVG is inlined in the app header. |
| `web/testmode.js` | **Local test mode.** When the built site is opened from `localhost`, the app uses a pretend Supabase that saves to localStorage, with a "Test learner" (test.learner@localhost) signed in. Any email and password sign in. That lets you test sync, tests, the account menu and feedback without a real account. A "Local test mode" badge shows in the header. `turkceTestMode.reset()` starts over; `.db()` and `.feedback()` show what was saved. Add `?supabase` to the URL to use the real backend. On the live site it's off unless someone clicks **Use test mode** in the sign-in panel. That's a pretend account kept in their browser, with a "Test mode" badge, until they click the **Test mode** badge to leave. Use that to test on the live site without a real account. |
| `build_site.py` | Builds `_site/`: adds the title, icons and Supabase scripts to the app, then copies `web/`. Never edit `_site/`. |
| `tools/make_sozluk.py` | Regenerates `sozluk.txt` from the DICTIONARY. Run it after every word change. |
| `sozluk.txt` | Plain-text copy of the Sözlük, kept in sync and committed. |
| `tools/RESTORE.md`, `tools/restore_backup.py` | Disaster recovery: the *Nightly backup* workflow (`.github/workflows/backup.yml`) saves an encrypted copy of everyone's data every night. The restore steps are in RESTORE.md. |
| `supabase/migrations/` | Database changes as numbered SQL files. They're applied by `.github/workflows/database.yml` after Jacob approves (see below). `20261007000000_user_docs.sql` is the original setup, already applied. |

## Adding words (Jacob's standing rules)
When Jacob says "add <turkish> - <english>":
1. **Use his gloss exactly as written.** Don't correct or extend it.
2. **Skip words that are already present.** Search the DICTIONARY for `"tr":"<word>"` (non-verbs) and `"inf":"<word>"` (verbs). If the word is already there in any list, don't add it, and tell him where it is.
3. **Collisions:** if the word is new but its English gloss is the same as, or nearly the same as, another word's, or the Turkish clashes with another sense, **don't decide alone**. Suggest how to resolve it and wait for his answer.
4. **Default list:** unless he names a list, add the word to the **Derste** lists. They're shown as "Derste" but stored as `"unit":"other"` for non-verbs and `"page":"other"` for verbs; the stored keys stayed the same so learners' saved data still matches.
5. **Topic:** also put every new word into one fitting topic (see below).
6. **Glosses of existing words** only change when he asks.
7. After the edits:
   1. Run `python3 tools/make_sozluk.py`.
   2. Run `python3 build_site.py` to check that it builds.
   3. Commit and push.

### Non-verb rows (`nonverbs` array)
`{"tr":"usta","en":"expert","unit":"other","order":771}`
- `unit` is one of `1`, `2` (Ünite sheets), `"other"`, `"sifatlar"` or `"bible"`.
- New Derste words: set `order` to one more than the highest `order` in the whole `nonverbs` array, and put the row at the end of the array (just before `],` / `topics: [`).
- Groups of 25 ("Derste 151-175") are made automatically from the order. A part-filled last group is fine.

### Verb rows (`verbs` array)
`{"inf":"yormak","base":"tire","ing":"tiring","past":"tired","pp":"tired","gloss":"to tire","num":null,"page":"other","order":204.1,"cases":[{"c":"akuzatif","en":"The long walk is tiring the children.","ex":"Uzun yürüyüş çocuk<b>ları</b> yoruyor."}]}`
- **English forms:**
  - `base`, `ing`, `past` and `pp` are the English forms the Forms tab uses to build prompts ("He tires", "They were tiring", …).
  - For several senses, separate them with ` / ` in every field, e.g. `"base":"save / deliver"`, `"gloss":"to save / to deliver"`.
- **Case example:** `cases` holds one example sentence.
  - `c` is the case label: `akuzatif`, `datif`, `lokatif`, `ablatif`, `ile`, or `örnek` for a plain example.
  - Wrap the case suffix in `<b>…</b>`.
  - Use the present continuous where natural.
- **New Derste verbs:** `"page":"other"`, with an `order` greater than the last `page:"other"` verb's and below 205 (the Bible verbs start at 205), e.g. 204.3, then 204.4. Put the row right after the last `page:"other"` row.
- **Check the conjugation:** load the page and run `conjugateFull(verb, tenseKey, personIdx, false, false, false)` for each key in `TENSES`. This catches Turkish verbs with unusual stems.

### Topics (`topics` array)
Each row is `{"key":"people","label":"People & Professions","terms":[...],"order":5}`. To place a word, append its Turkish form to that topic's `terms`. Available keys:
- question, numbers, time, politeness, people, places, furniture, kitchen
- transport, media, personality, school, shopping, hobbies, common, startfinish
- colors, clothes, winterwear, jewelry, nature, directions, feelings, routine
- health, communication, movement, actions, thinking, describing, littlewords, cities
- weather, films, tastes, character, opposites, faith, salvation, worship

## Database changes (Supabase)
The database holds only per-person data: one table, `public.user_docs (user_id, doc, data jsonb, writer, updated_at)`, with row-level security so each signed-in person sees only their own rows. The `doc` values are `settings`, `progress`, `wordstats`, `meta` and `tests/lists/<key>`. The function `merge_doc(p_doc, p_patch, p_writer)` deep-merges a patch, and realtime is on for the table.

To change the database:
1. Add a **new** file `supabase/migrations/<YYYYMMDDHHMMSS>_<short_name>.sql`, using the current UTC time. Never edit or rename a migration that's already on `main`.
2. Write plain Postgres SQL. Make it safe to re-run where possible (`if not exists`, `create or replace`).
3. Never drop or delete learners' data unless Jacob explicitly asked for exactly that.
4. Push to `main`. The *Apply database changes* workflow then waits for Jacob's approval.
5. Tell him: *"Approve it in GitHub → Actions → Apply database changes → Review deployments."*
6. Nothing touches the database until he approves. If the SQL fails, the workflow fails and nothing is half-applied, because each migration runs in a transaction.

**Not possible from here:**
- **Sign-in settings** (Authentication config). Those need the Supabase CLI on Jacob's Mac.
- **Moving a learner's progress from the old Claude site.** That needs a Claude session with access to that site.

## Feedback ("Suggest a change")
The "Suggest a change" button in the header (a speech bubble) saves a suggestion into the Supabase `feedback` table. People can send suggestions whether or not they're signed in, and the public can't read them back. They can attach a screenshot: the camera button dims the page, they drag over an area (or tap for the whole screen), and html2canvas (loaded from jsDelivr only when needed) renders it into a PNG or JPEG stored in the row's `screenshot` column. A signed-in sender's email is stored too.

Feedback is **private** and isn't copied anywhere else. Jacob reviews it through his Mac session, which reads the table with the Supabase CLI. A row whose `synced_at` is set has been handled. Cloud sessions have no database access, so they can't see feedback. (Issues #1 and #2 on GitHub are from an earlier setup that copied feedback there.)

## Other notes
- **Learners' saved data** is keyed by the Turkish word, e.g. `"nonverb:usta"` or `"verb:yormak"`. Renaming a word's Turkish spelling orphans learners' history for it. Changing the English gloss is safe.
- **Before pushing a UI change,** preview `_site/` in a browser if you can, and keep it working at phone width.
- **The old Claude-artifact version** of the app is frozen. It's used only for its "Send my progress to the new site" button, and it isn't in this repo.
