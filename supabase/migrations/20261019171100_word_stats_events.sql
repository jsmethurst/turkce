-- Data safety, part 2: word stats become a real table (one row per learner and word),
-- and every answer is logged. The old "wordstats" document is kept as it is.
-- Safe to re-run. The new tables are filled from the existing data, which is not changed.

-- ---------- word_stats: one row per learner and word ----------
create table if not exists public.word_stats (
  user_id    uuid not null default auth.uid() references auth.users on delete cascade,
  key        text not null,                 -- "verb:<infinitive>" or "nonverb:<word>"
  r          text not null,                 -- last answers, oldest first: 1 = right, 0 = wrong (at most 25)
  at         timestamptz not null,          -- when it was last answered
  writer     text,                          -- which browser tab wrote it last (so a tab ignores its own echoes)
  updated_at timestamptz not null default now(),
  primary key (user_id, key),
  constraint word_stats_key_ck check (key ~ '^(verb|nonverb):.{1,90}$'),
  constraint word_stats_r_ck   check (r ~ '^[01]{1,25}$')
);
alter table public.word_stats enable row level security;
drop policy if exists "own rows: read" on public.word_stats;
create policy "own rows: read" on public.word_stats for select to authenticated using (user_id = (select auth.uid()));
-- Learners read their own rows; writing goes through the functions below only.
revoke all on public.word_stats from anon, authenticated;
grant select on public.word_stats to authenticated;

-- ---------- answer_events: every answer, for usage numbers ----------
create table if not exists public.answer_events (
  id      bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  at      timestamptz not null default now(),
  tab     text not null check (tab in ('forms', 'vocab', 'tekrar', 'cases')),
  key     text check (key is null or char_length(key) <= 100),
  correct boolean not null
);
create index if not exists answer_events_user_at_idx on public.answer_events (user_id, at desc);
alter table public.answer_events enable row level security;
drop policy if exists "own rows: read" on public.answer_events;
create policy "own rows: read" on public.answer_events for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.answer_events from anon, authenticated;
grant select on public.answer_events to authenticated;

-- ---------- fill word_stats from the existing wordstats documents ----------
insert into public.word_stats (user_id, key, r, at, writer)
select d.user_id, e.key, e.value ->> 'r', (e.value ->> 'at')::timestamptz, 'migration'
from public.user_docs d, jsonb_each(d.data -> 'words') e
where d.doc = 'wordstats'
  and e.key ~ '^(verb|nonverb):.{1,90}$'
  and e.value ->> 'r' ~ '^[01]{1,25}$'
  and e.value ->> 'at' ~ '^\d{4}-\d\d-\d\d'
on conflict (user_id, key) do nothing;

-- ---------- remembering the batches already applied (so a retry never counts twice) ----------
create table if not exists private.applied_batches (
  user_id    uuid not null,
  batch_id   text not null,
  applied_at timestamptz not null default now(),
  primary key (user_id, batch_id)
);
revoke all on private.applied_batches from public, anon, authenticated;

-- ---------- saving answers: append, never overwrite ----------
-- p_items: [{"k": "nonverb:usta" | null, "tab": "vocab", "ok": true, "at": "<time>", "s": true}, ...]
-- "s" means the answer also counts toward the word's history (Vocab and Tekrar).
-- A bad item is skipped; it can't block the rest. Sending the same batch id twice does nothing.
create or replace function public.append_word_answers(p_batch_id text, p_items jsonb, p_writer text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  it jsonb;
  t timestamptz;
  good boolean;
begin
  if me is null then raise exception 'not signed in'; end if;
  if p_batch_id is null or char_length(p_batch_id) > 80 then raise exception 'bad batch id'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 500 then
    raise exception 'bad items';
  end if;

  insert into private.applied_batches (user_id, batch_id) values (me, p_batch_id)
  on conflict do nothing;
  if not found then return; end if;
  delete from private.applied_batches where user_id = me and applied_at < now() - interval '3 days';

  for it in select * from jsonb_array_elements(p_items) loop
    begin
      t := least(coalesce((it ->> 'at')::timestamptz, now()), now());
      good := (it ->> 'ok')::boolean;
      insert into public.answer_events (user_id, at, tab, key, correct)
      values (me, t, it ->> 'tab', it ->> 'k', good);
      if coalesce((it ->> 's')::boolean, false) and (it ->> 'k') is not null then
        insert into public.word_stats as w (user_id, key, r, at, writer, updated_at)
        values (me, it ->> 'k', case when good then '1' else '0' end, t, p_writer, now())
        on conflict (user_id, key) do update
          set r = right(w.r || excluded.r, 25),
              at = greatest(w.at, excluded.at),
              writer = excluded.writer,
              updated_at = now();
      end if;
    exception when others then
      null;   -- skip this item only
    end;
  end loop;
end $$;
revoke all on function public.append_word_answers(text, jsonb, text) from public, anon;
grant execute on function public.append_word_answers(text, jsonb, text) to authenticated;

-- One-time: a device that has word history the account doesn't have yet sends it here.
-- Only words the account has no row for are added; nothing existing is touched.
create or replace function public.import_word_stats(p_words jsonb, p_writer text)
returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if p_words is null or jsonb_typeof(p_words) <> 'object' then raise exception 'bad words'; end if;
  insert into public.word_stats (user_id, key, r, at, writer)
  select me, e.key, e.value ->> 'r', (e.value ->> 'at')::timestamptz, p_writer
  from jsonb_each(p_words) e
  where e.key ~ '^(verb|nonverb):.{1,90}$'
    and e.value ->> 'r' ~ '^[01]{1,25}$'
    and e.value ->> 'at' ~ '^\d{4}-\d\d-\d\d'
  limit 3000
  on conflict (user_id, key) do nothing;
end $$;
revoke all on function public.import_word_stats(jsonb, text) from public, anon;
grant execute on function public.import_word_stats(jsonb, text) to authenticated;

-- ---------- a page that is still the old version keeps writing the old document ----------
-- Carry anything newer from it into word_stats until nobody runs the old page any more.
create or replace function private.carry_old_wordstats()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.doc = 'wordstats' and jsonb_typeof(new.data -> 'words') = 'object' then
    insert into public.word_stats as w (user_id, key, r, at, writer)
    select new.user_id, e.key, e.value ->> 'r', (e.value ->> 'at')::timestamptz, 'old-page'
    from jsonb_each(new.data -> 'words') e
    where e.key ~ '^(verb|nonverb):.{1,90}$'
      and e.value ->> 'r' ~ '^[01]{1,25}$'
      and e.value ->> 'at' ~ '^\d{4}-\d\d-\d\d'
    on conflict (user_id, key) do update
      set r = excluded.r, at = excluded.at, writer = excluded.writer, updated_at = now()
      where excluded.at > w.at;
  end if;
  return null;
end $$;
revoke all on function private.carry_old_wordstats() from public, anon, authenticated;
drop trigger if exists carry_old_wordstats on public.user_docs;
create trigger carry_old_wordstats after insert or update on public.user_docs
  for each row execute function private.carry_old_wordstats();

-- ---------- daily snapshots of each learner's word_stats (kept 14 days) ----------
create table if not exists private.word_stats_history (
  user_id      uuid not null,
  snapshot_day date not null,
  data         jsonb not null,
  taken_at     timestamptz not null default now(),
  primary key (user_id, snapshot_day)
);
revoke all on private.word_stats_history from public, anon, authenticated;

create or replace function private.snapshot_word_stats()
returns trigger language plpgsql security definer set search_path = '' as $$
declare uid uuid := new.user_id;
begin
  if not exists (select 1 from private.word_stats_history
                 where user_id = uid and snapshot_day = (now() at time zone 'utc')::date) then
    insert into private.word_stats_history (user_id, snapshot_day, data)
    select uid, (now() at time zone 'utc')::date,
           coalesce(jsonb_object_agg(s.key, jsonb_build_object('r', s.r, 'at', s.at)), '{}'::jsonb)
    from public.word_stats s where s.user_id = uid
    on conflict do nothing;
    delete from private.word_stats_history
    where user_id = uid and snapshot_day < (now() at time zone 'utc')::date - 14;
  end if;
  return new;
end $$;
revoke all on function private.snapshot_word_stats() from public, anon, authenticated;
drop trigger if exists word_stats_snapshot on public.word_stats;
create trigger word_stats_snapshot before insert or update on public.word_stats
  for each row execute function private.snapshot_word_stats();

-- ---------- live sync between a person's devices ----------
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'word_stats') then
    alter publication supabase_realtime add table public.word_stats;
  end if;
end $$;

-- ---------- the nightly backup now includes both new tables ----------
create or replace function public.backup_export()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'exported_at', now(),
    'users', coalesce((
      select jsonb_agg(jsonb_build_object(
               'email', u.email,
               'created_at', u.created_at,
               'docs', coalesce((
                 select jsonb_object_agg(d.doc, d.data)
                 from public.user_docs d
                 where d.user_id = u.id
               ), '{}'::jsonb),
               'word_stats', coalesce((
                 select jsonb_object_agg(w.key, jsonb_build_object('r', w.r, 'at', w.at))
                 from public.word_stats w
                 where w.user_id = u.id
               ), '{}'::jsonb),
               'answer_events', coalesce((
                 select jsonb_agg(jsonb_build_array(e.at, e.tab, e.key, e.correct) order by e.at)
                 from public.answer_events e
                 where e.user_id = u.id
               ), '[]'::jsonb))
             order by u.email)
      from auth.users u
    ), '[]'::jsonb)
  );
$$;
