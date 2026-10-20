-- Forms answers in detail: for every answer, which tense, person, negative / question / ability,
-- direction, how long it took, and whether it was in a timed test. That lets the weakest
-- combinations be worked out from the whole history. Safe to re-run; no existing data is changed
-- (answers logged before this just have these columns empty).

alter table public.answer_events add column if not exists tense    text;
alter table public.answer_events add column if not exists person   smallint;
alter table public.answer_events add column if not exists negative boolean;
alter table public.answer_events add column if not exists question boolean;
alter table public.answer_events add column if not exists ability  boolean;
alter table public.answer_events add column if not exists mode     text;
alter table public.answer_events add column if not exists ms       integer;
alter table public.answer_events add column if not exists timed    boolean;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'answer_events_detail_ck') then
    alter table public.answer_events add constraint answer_events_detail_ck check (
      (tense  is null or tense ~ '^[a-z_]{1,40}$')
      and (person is null or person between 0 and 5)
      and (mode   is null or mode in ('en2tr', 'tr', 'tr2en'))
      and (ms     is null or ms between 0 and 3600000));
  end if;
end $$;

create index if not exists answer_events_forms_idx on public.answer_events (user_id, tense, person) where tab = 'forms';

-- Saving answers: same as before, plus the detail fields.
-- p_items: [{"k", "tab", "ok", "at", "s", "tn": tense, "p": person, "ng", "q", "ab", "md": direction, "ms", "ts": timed}, ...]
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
      insert into public.answer_events (user_id, at, tab, key, correct, tense, person, negative, question, ability, mode, ms, timed)
      values (me, t, it ->> 'tab', it ->> 'k', good,
              it ->> 'tn', (it ->> 'p')::smallint, (it ->> 'ng')::boolean, (it ->> 'q')::boolean, (it ->> 'ab')::boolean,
              it ->> 'md', (it ->> 'ms')::integer, (it ->> 'ts')::boolean);
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

-- The nightly backup carries the new fields too (appended to each answer: tense, person, negative, question, ability, direction, ms, timed).
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
                 select jsonb_agg(jsonb_build_array(e.at, e.tab, e.key, e.correct,
                                                    e.tense, e.person, e.negative, e.question, e.ability, e.mode, e.ms, e.timed)
                                  order by e.at)
                 from public.answer_events e
                 where e.user_id = u.id
               ), '[]'::jsonb))
             order by u.email)
      from auth.users u
    ), '[]'::jsonb)
  );
$$;
