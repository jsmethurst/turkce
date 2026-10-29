# Türkçe — Turkish verb & vocabulary drill

Live site: https://jsmethurst.github.io/turkce/ (owner: Jacob, jsmethurst). It's a single-page app with three tabs:
- **Forms:** conjugation drills.
- **Vocab:** flashcards and tests.
- **Sözlük:** the word lists, in two views: *List selection* (default: choose which lists to practice) and *Progress* (the color summary and every word in the same list order). Topics are switched off for now (`TOPICS_ON = false` in the page; the code and data stay).

Learners sign in with email and password through Supabase so their progress syncs between devices.

## Time zone
Jacob works in **UTC+3** (Turkey, Istanbul; no daylight saving). Always give times to him in that time zone, not UTC, including in progress reports and database lookups. Database timestamps are stored in UTC, so convert them before reporting.

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
| `web/favicon.svg`, `favicon-32.png`, `apple-touch-icon.jpg` | Logo and icons (a smiling çay glass, the Chalk version). The header logo and the browser-tab icon are drawn by `turkceLogoSVG`/`renderLogo` in the app, with a palette per theme (`LOGO`), so they change with the theme; these static files are only the fallback. |
| `web/testmode.js` | **Local test mode.** When the built site is opened from `localhost`, the app uses a pretend Supabase that saves to localStorage, with a "Test learner" (test.learner@localhost) signed in. Any email and password sign in. That lets you test sync, tests, the account menu and feedback without a real account. A "Local test mode" badge shows in the header. `turkceTestMode.reset()` starts over; `.db()` and `.feedback()` show what was saved. Add `?supabase` to the URL to use the real backend. On the live site it's off unless someone clicks **Use test mode** in the sign-in panel. That's a pretend account kept in their browser, with a "Test mode" badge, until they click the **Test mode** badge to leave. Use that to test on the live site without a real account. |
| `build_site.py` | Builds `_site/`: adds the title, icons and Supabase scripts to the app, then copies `web/`. Never edit `_site/`. |
| `tools/make_sozluk.py` | Regenerates `sozluk.txt` from the DICTIONARY. Run it after every word change. |
| `sozluk.txt` | Plain-text copy of the Sözlük, kept in sync and committed. |
| `tools/RESTORE.md`, `tools/restore_backup.py` | Disaster recovery: the *Nightly backup* workflow (`.github/workflows/backup.yml`) saves an encrypted copy of everyone's data every night. The restore steps are in RESTORE.md. |
| `supabase/migrations/` | Database changes as numbered SQL files. They're applied by `.github/workflows/database.yml` after Jacob approves (see below). `20261007000000_user_docs.sql` is the original setup, already applied. |

## Word lists: A1 (frozen) and Personal
The built-in lists are the **A1** lists (Listede: the Sayfa and Ünite lists and Sıfatlar; Derste): everyone gets them from the page. Jacob will not ask for more words to be added to A1; he may ask for a gloss edit here and there. In the Sözlük they sit in a solid box; a dotted box above it holds **Personal - editable**.

Personal lists are stored per learner in the database (`public.user_lists`, `public.user_terms`), not in the page: each learner (signed in) can add, rename and delete lists, and add, edit and remove terms (**Manage** in the dotted box). Non-verbs can be added in bulk ("Turkish, English" per line); verbs one at a time, with English forms suggested from the meaning. A list is numbered into groups of 25 automatically: a list called "Test" shows as "Test 1-5", then "Test 1-25" and "Test 26-50" as words are added (a name that already ends in a range, like "Bible 1-25", is left alone). The first group keeps the list's own key; later groups use `<key>_c1`, `_c2`... A signed-out visitor sees an empty Personal box. Every learner, current and new, has the Bible lists: Bible 1-25 (verbs and non-verbs) and the non-verb lists Bible 26-50, 51-75 and 76-100. New signups get them from a trigger on `auth.users` (`private.seed_bible_lists`, words in `private.bible_seed`; a failure there never blocks a signup). The old built-in Bible words are no longer in the page. Don't add new words to the built-in dictionary until Jacob says where they go.

## Term keys: changing a word's Turkish without losing progress
Learners' progress is saved under each term's **permanent key**, not its spelling. For a built-in term the key is the row's `"k"` field, or `nonverb:<turkish>` / `verb:<infinitive>` when there is no `"k"`. To change the Turkish of a built-in term, keep its old key by adding `"k":"nonverb:<old spelling>"` (or `"verb:..."`) to the row, then change `tr`/`inf`. The English gloss can always change freely. `tools/term_keys.json` remembers every key ever used and `tools/check_term_keys.py` (run by `build_site.py`, so also by the deploy) fails the build if one of them no longer resolves to a term; that stops an accidental respelling from orphaning anyone's history. Personal-list terms have a uuid `id` and a permanent `pkey` of their own (`nonverb:u_<12 hex>`; the seeded Bible terms kept their old keys), so a learner can change the Turkish or English freely without losing progress.

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
   2. Run `python3 tools/check_term_keys.py --update` (remembers the new words' progress keys).
   3. Run `python3 build_site.py` to check that it builds.
   4. Commit and push.

### Non-verb rows (`nonverbs` array)
`{"tr":"usta","en":"expert","unit":"other","order":771}`
- `unit` is one of `1`, `2` (Ünite sheets), `"other"`, `"sifatlar"` or `"bible"`. (There used to be a separate "common" group; those words now sit at the end of Derste.)
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
The database holds only per-person data, with row-level security so each signed-in person sees only their own rows:
- `public.user_docs (user_id, doc, data jsonb, writer, updated_at)`: settings, progress, meta and test results. The old `wordstats` doc is kept but frozen: a trigger (`private.carry_old_wordstats`) copies anything an old cached page still writes into `word_stats`. Drop that trigger once nobody runs the old page.
- `public.word_stats (user_id, key, r, at, writer, updated_at)`: one row per learner and word. Learners can only read it; the page saves answers by calling `append_word_answers(batch_id, items, writer)`, which appends to `r` (never overwrites) and is safe to retry.
- `public.answer_events`: one row per answer (forms, vocab, tekrar, cases), written by the same function, for usage numbers.
- `public.user_lists (id uuid, user_id, kind verb|nonverb, name, seed, deleted_at, ...)` and `public.user_terms (id uuid, user_id, list_id, kind, pkey, tr, en, forms jsonb, position, deleted_at, ...)`: each learner's own lists and terms. Rows are never really deleted (`deleted_at` is set, so a mistake can be undone); `pkey` is the permanent key progress is saved under (a trigger fills it in and forbids changing it); `forms` holds a verb's English forms. Row-level security: own rows only. The nightly backup and `tools/restore_backup.py` include both tables.
- `private.user_docs_history` and `private.word_stats_history`: one snapshot a day for 14 days, the undo for bad writes. `backups.*_20261019`: plain copies from before the 19 Oct 2026 upgrade.

The `doc` values are `settings`, `progress`, `wordstats`, `meta` and `tests/lists/<key>`. The function `merge_doc(p_doc, p_patch, p_writer)` deep-merges a patch, and realtime is on for the table.

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

## Theme and typeface
Six themes, chosen as little color chips at the bottom of the gear (Global Settings) menu: three light (**Chalk** = default, **Meadow**, **Ember**) and three dark (**Night**, **Moss**, **Coal**). Light themes are white and very light grey, dark themes near-black and dark grey; color is only an accent (selected lists and chips get a light tint, an accent outline and a check; buttons and the active tab use the solid accent; a list whose test is due gets a small red dot). Each theme also sets the typeface (`--font`): Chalk and Moss use Figtree, Meadow and Coal Atkinson Hyperlegible, Ember Lexend, Night Nunito Sans. The typefaces are self-hosted in `web/fonts/` (latin and latin-ext, so every Turkish letter works; see `web/fonts/fonts.css`), no Google Fonts.

All colors are CSS variables set per theme at the top of `app/turkish-verb-drill.html` (`:root[data-theme="..."]`); use `var(--surface)`, `var(--heading)`, `var(--font)` and the other variables, not hard-coded colors or font names, so every theme keeps working. The choice is saved with the learner's settings (`theme`) and in `localStorage` (`turkce_theme`) so the page paints in the right theme at once. Old saved values `light`/`dark`/`device` are mapped to Chalk/Night/(device preference) on load. The chip swatch colors in `web/backend.js` (`gs-theme-chip`) repeat each theme's main colors.

## Guide and feedback buttons
"How to use Türkçe" is a short guide written by Jacob. It sits in an expandable section at the bottom of the gear (Global Settings) menu, in `buildSettings` in `web/backend.js` (the "?" button was removed from the header). Keep its wording as he wrote it.

## Feedback ("Suggest a change")
The "Suggest a change" button in the header (a speech bubble) saves a suggestion into the Supabase `feedback` table. People can send suggestions whether or not they're signed in, and the public can't read them back. They can attach a screenshot: the camera button dims the page, they drag over an area (or tap for the whole screen), and html2canvas (loaded from jsDelivr only when needed) renders it into a PNG or JPEG stored in the row's `screenshot` column. A signed-in sender's email is stored too.

Feedback is **private** and isn't copied anywhere else. Jacob reviews it through his Mac session, which reads the table with the Supabase CLI. `tools/feedback_report.py` prints it readably when Jacob asks (`--done N` marks items handled). A row whose `synced_at` is set has been handled. Cloud sessions have no database access, so they can't see feedback.

## Other notes
- **Learners' saved data** is keyed by the Turkish word, e.g. `"nonverb:usta"` or `"verb:yormak"`. Renaming a word's Turkish spelling orphans learners' history for it. Changing the English gloss is safe.
- **Before pushing a UI change,** preview `_site/` in a browser if you can, and keep it working at phone width.
- **The old Claude-artifact version** of the app is frozen. It's used only for its "Send my progress to the new site" button, and it isn't in this repo.
