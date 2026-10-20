-- Finishes 20261020080000_forms_answer_detail: that migration's columns, check, index and backup_export
-- are already in place, but its replacement of append_word_answers was never applied (the database tool
-- stalled on it). This one puts the new version of the function in. Safe to re-run.

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
