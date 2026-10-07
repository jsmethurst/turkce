# Disaster recovery

What lives where:
- **Website and word list:** this repo. It rebuilds on every push.
- **Database structure** (table, privacy rules, functions): `supabase/migrations/`.
- **Learners' saved data:** in Supabase, plus a nightly encrypted backup (*Nightly backup* workflow). Each backup is kept for 30 days and needs Jacob's passphrase to open.

## If the Supabase project is lost
1. **Create a new project.** Then update `SUPABASE_URL` and `SUPABASE_KEY` in `web/backend.js`, and the project ref in `.github/workflows/*.yml`.
2. **Recreate the structure.** Run `supabase link --project-ref <new ref>`, then `supabase db push --linked`.
3. **Sign-in settings.** In Authentication:
   - turn **Confirm email** off,
   - set the **Site URL** to `https://jsmethurst.github.io/turkce/`,
   - add the same address under **Redirect URLs**.
4. **Backups.**
   - Set a password for the `backup_reader` role (`alter role backup_reader with login password '…'`).
   - Update the `BACKUP_DB_URL` secret in the **backup** environment to `postgresql://backup_reader.<ref>:<password>@<pooler host>:5432/postgres`.
   - Re-add `SUPABASE_ACCESS_TOKEN` to the **database** environment.
5. **Ask everyone to sign up again** with the same email.
6. **Restore their data:**
   1. Download the latest backup file: GitHub → Actions → *Nightly backup* → latest run → Artifacts.
   2. Unzip it, then run `python3 tools/restore_backup.py turkce-backup-….json.enc > /tmp/restore.sql`. It asks for the passphrase.
   3. Run `supabase db query --linked -f /tmp/restore.sql`, then delete `/tmp/restore.sql`.
   4. The last statement lists anyone who hasn't signed up yet. Re-run the restore after they do.

The restore SQL contains learners' data. **Never commit it.**
