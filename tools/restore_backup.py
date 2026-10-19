#!/usr/bin/env python3
"""Turn a nightly backup into SQL that puts everyone's data back.

    python3 tools/restore_backup.py turkce-backup-YYYY-MM-DD.json.enc > /tmp/restore.sql

It asks for the backup passphrase (openssl prompts for it), decrypts in memory,
and prints SQL that writes each person's docs into public.user_docs (plus their word_stats and answer_events) for the
account with the same email. People must have signed up again first; anyone
without an account is listed as a comment at the end.

The SQL contains learners' data: never commit it. Apply it from Jacob's Mac:
    supabase db query --linked -f /tmp/restore.sql
See tools/RESTORE.md.
"""
import json
import os
import subprocess
import sys


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    cmd = ["openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2", "-iter", "200000", "-in", sys.argv[1]]
    if os.environ.get("BACKUP_PASSPHRASE"):   # otherwise openssl asks for it
        cmd += ["-pass", "env:BACKUP_PASSPHRASE"]
    plain = subprocess.run(cmd, check=True, stdout=subprocess.PIPE).stdout
    backup = json.loads(plain)
    out = [f"-- Restore from backup exported at {backup['exported_at']}", "begin;"]
    for user in backup["users"]:
        email = user["email"].replace("'", "''")
        for doc, data in sorted(user["docs"].items()):
            body = json.dumps(data, ensure_ascii=False)
            if "$restore$" in body:
                sys.exit("unexpected delimiter in data")
            out.append(
                "insert into public.user_docs (user_id, doc, data, writer, updated_at)\n"
                f"select u.id, '{doc.replace(chr(39), chr(39) * 2)}', $restore${body}$restore$::jsonb, 'restore', now()\n"
                f"from auth.users u where lower(u.email) = lower('{email}')\n"
                "on conflict (user_id, doc) do update set data = excluded.data, writer = excluded.writer, updated_at = now();")
        # word_stats and answer_events came in later backups; older files simply don't have them.
        ws = user.get("word_stats") or {}
        if ws:
            body = json.dumps(ws, ensure_ascii=False)
            if "$restore$" in body:
                sys.exit("unexpected delimiter in data")
            out.append(
                "insert into public.word_stats (user_id, key, r, at, writer)\n"
                f"select u.id, e.key, e.value->>'r', (e.value->>'at')::timestamptz, 'restore'\n"
                f"from auth.users u, jsonb_each($restore${body}$restore$::jsonb) e where lower(u.email) = lower('{email}')\n"
                "on conflict (user_id, key) do update set r = excluded.r, at = excluded.at, writer = excluded.writer, updated_at = now();")
        ev = user.get("answer_events") or []
        if ev:
            body = json.dumps(ev, ensure_ascii=False)
            if "$restore$" in body:
                sys.exit("unexpected delimiter in data")
            out.append(
                "insert into public.answer_events (user_id, at, tab, key, correct)\n"
                "select u.id, (e->>0)::timestamptz, e->>1, e->>2, (e->>3)::boolean\n"
                f"from auth.users u, jsonb_array_elements($restore${body}$restore$::jsonb) e where lower(u.email) = lower('{email}')\n"
                "and not exists (select 1 from public.answer_events x where x.user_id = u.id and x.at = (e->>0)::timestamptz\n"
                "  and x.tab = e->>1 and coalesce(x.key, '') = coalesce(e->>2, '') and x.correct = (e->>3)::boolean);")
    out.append("commit;")
    out.append("-- Accounts in the backup with no matching account now (they need to sign up, then re-run):")
    out.append("select b.email from (values " +
               ", ".join("('" + u["email"].replace("'", "''") + "')" for u in backup["users"]) +
               ") as b(email) where not exists (select 1 from auth.users u where lower(u.email) = lower(b.email));"
               if backup["users"] else "-- (none)")
    print("\n".join(out))


if __name__ == "__main__":
    main()
