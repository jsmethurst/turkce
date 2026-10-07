-- Türkçe: per-user data (settings, progress, word stats, test scores).
-- Paste all of this into Supabase → SQL Editor → New query, then click Run.
-- The word list itself lives in the page, so it needs no table.

create table if not exists public.user_docs (
  user_id    uuid not null default auth.uid() references auth.users on delete cascade,
  doc        text not null,               -- "settings", "progress", "wordstats", "meta", "tests/lists/<key>"
  data       jsonb not null default '{}'::jsonb,
  writer     text,                        -- which browser tab wrote it last (so a tab ignores its own echoes)
  updated_at timestamptz not null default now(),
  primary key (user_id, doc)
);

alter table public.user_docs enable row level security;

-- Each person can only see and change their own rows.
drop policy if exists "own rows: read"   on public.user_docs;
drop policy if exists "own rows: insert" on public.user_docs;
drop policy if exists "own rows: update" on public.user_docs;
drop policy if exists "own rows: delete" on public.user_docs;
create policy "own rows: read"   on public.user_docs for select to authenticated using (user_id = auth.uid());
create policy "own rows: insert" on public.user_docs for insert to authenticated with check (user_id = auth.uid());
create policy "own rows: update" on public.user_docs for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own rows: delete" on public.user_docs for delete to authenticated using (user_id = auth.uid());

revoke all on public.user_docs from anon;
grant select, insert, update, delete on public.user_docs to authenticated;

-- Merge nested objects (e.g. add one word's stats without resending all of them).
create or replace function public.jsonb_deep_merge(a jsonb, b jsonb)
returns jsonb language plpgsql immutable as $$
declare k text; result jsonb;
begin
  if a is null or jsonb_typeof(a) <> 'object' or b is null or jsonb_typeof(b) <> 'object' then
    return b;
  end if;
  result := a;
  for k in select jsonb_object_keys(b) loop
    result := jsonb_set(result, array[k], public.jsonb_deep_merge(a -> k, b -> k));
  end loop;
  return result;
end $$;

-- Save part of a document, creating it if needed. Runs as the signed-in user, so the rules above still apply.
create or replace function public.merge_doc(p_doc text, p_patch jsonb, p_writer text)
returns void language sql security invoker as $$
  insert into public.user_docs as d (user_id, doc, data, writer, updated_at)
  values (auth.uid(), p_doc, p_patch, p_writer, now())
  on conflict (user_id, doc) do update
    set data = public.jsonb_deep_merge(d.data, excluded.data),
        writer = excluded.writer,
        updated_at = now();
$$;

revoke execute on function public.merge_doc(text, jsonb, text) from public, anon;
grant execute on function public.merge_doc(text, jsonb, text) to authenticated;

-- Live sync between a person's devices.
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'user_docs') then
    alter publication supabase_realtime add table public.user_docs;
  end if;
end $$;
