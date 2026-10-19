-- Data safety, part 1: a copy of today's data, tighter functions and rules, and daily snapshots.
-- Every statement is safe to re-run. Nothing here deletes or changes anyone's saved data.

-- 1. A plain copy of everything, taken before any other change in this file.
--    The schema isn't exposed through the API, so learners can't see it.
create schema if not exists backups;
revoke all on schema backups from public, anon, authenticated;
create table if not exists backups.user_docs_20261019 as table public.user_docs;
create table if not exists backups.feedback_20261019 as table public.feedback;
revoke all on all tables in schema backups from public, anon, authenticated;

-- 2. Fix the search path of the two merge functions (security advisor warning).
alter function public.jsonb_deep_merge(jsonb, jsonb) set search_path = public, pg_temp;
alter function public.merge_doc(text, jsonb, text)   set search_path = public, pg_temp;

-- 3. Rules: look up the signed-in user once per query instead of once per row (performance advisor warning).
drop policy if exists "own rows: read"   on public.user_docs;
drop policy if exists "own rows: insert" on public.user_docs;
drop policy if exists "own rows: update" on public.user_docs;
drop policy if exists "own rows: delete" on public.user_docs;
create policy "own rows: read"   on public.user_docs for select to authenticated using (user_id = (select auth.uid()));
create policy "own rows: insert" on public.user_docs for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own rows: update" on public.user_docs for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "own rows: delete" on public.user_docs for delete to authenticated using (user_id = (select auth.uid()));

-- 4. Limits: only the document names the app uses, and no single document over 1 MB.
--    (Every existing row already passes: the largest is 18 kB.)
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'user_docs_doc_name_ck') then
    alter table public.user_docs add constraint user_docs_doc_name_ck
      check (doc ~ '^(settings|progress|wordstats|meta|tests/lists/[A-Za-z0-9_]+)$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'user_docs_size_ck') then
    alter table public.user_docs add constraint user_docs_size_ck
      check (pg_column_size(data) <= 1000000);
  end if;
end $$;

-- 5. Daily snapshots: the first time a document changes each day, keep how it looked
--    just before (kept for 14 days). This is the undo for mistakes and bad writes.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.user_docs_history (
  user_id      uuid not null,
  doc          text not null,
  snapshot_day date not null,
  data         jsonb not null,
  taken_at     timestamptz not null default now(),
  primary key (user_id, doc, snapshot_day)
);
revoke all on private.user_docs_history from public, anon, authenticated;

create or replace function private.snapshot_user_doc()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.doc in ('settings', 'progress', 'wordstats') then
    insert into private.user_docs_history (user_id, doc, snapshot_day, data)
    values (old.user_id, old.doc, (now() at time zone 'utc')::date, old.data)
    on conflict (user_id, doc, snapshot_day) do nothing;
    if found then   -- a new day's snapshot was just taken: tidy up the old ones
      delete from private.user_docs_history
      where user_id = old.user_id and snapshot_day < (now() at time zone 'utc')::date - 14;
    end if;
  end if;
  return new;
end $$;
revoke all on function private.snapshot_user_doc() from public, anon, authenticated;

drop trigger if exists user_docs_snapshot on public.user_docs;
create trigger user_docs_snapshot before update on public.user_docs
  for each row execute function private.snapshot_user_doc();
