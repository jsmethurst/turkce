-- Bug reports and feedback from the bug button in the header.
-- Anyone (signed in or not) can add a row; nobody can read them through the
-- site. The "Sync feedback" workflow turns new rows into GitHub Issues using a
-- dedicated login (feedback_sync) that can only call the two functions below.

create table if not exists public.feedback (
  id           bigint generated always as identity primary key,
  created_at   timestamptz not null default now(),
  user_id      uuid,                 -- set by the trigger from the sign-in, never by the client
  email        text,                 -- likewise; kept here only, not copied into GitHub
  kind         text not null default 'bug' check (kind in ('bug', 'idea')),
  message      text not null check (char_length(btrim(message)) between 1 and 4000),
  context      text check (char_length(context) <= 1000),    -- tab and what was on screen
  user_agent   text check (char_length(user_agent) <= 400),
  issue_number integer,
  synced_at    timestamptz
);

alter table public.feedback enable row level security;

-- Whoever sends it, the sender's identity comes from their sign-in (or is empty),
-- and the GitHub columns start empty.
create or replace function public.feedback_stamp()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.user_id := auth.uid();
  new.email := nullif(auth.jwt() ->> 'email', '');
  new.created_at := now();
  new.issue_number := null;
  new.synced_at := null;
  return new;
end $$;

drop trigger if exists feedback_stamp on public.feedback;
create trigger feedback_stamp before insert on public.feedback
  for each row execute function public.feedback_stamp();

drop policy if exists "anyone can send feedback" on public.feedback;
create policy "anyone can send feedback" on public.feedback
  for insert to anon, authenticated with check (true);

revoke all on public.feedback from anon, authenticated;
grant insert (kind, message, context, user_agent) on public.feedback to anon, authenticated;

-- For the sync workflow only.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'feedback_sync') then
    create role feedback_sync nologin noinherit;
  end if;
end $$;

create or replace function public.feedback_pending()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', f.id, 'created_at', f.created_at, 'kind', f.kind,
           'message', f.message, 'context', f.context, 'user_agent', f.user_agent,
           'signed_in', f.user_id is not null)
         order by f.id), '[]'::jsonb)
  from public.feedback f
  where f.issue_number is null;
$$;

create or replace function public.feedback_mark_synced(p_id bigint, p_issue integer)
returns void language sql security definer set search_path = '' as $$
  update public.feedback set issue_number = p_issue, synced_at = now()
  where id = p_id and issue_number is null;
$$;

revoke all on function public.feedback_pending() from public, anon, authenticated;
revoke all on function public.feedback_mark_synced(bigint, integer) from public, anon, authenticated;
revoke all on function public.feedback_stamp() from public, anon, authenticated;
grant usage on schema public to feedback_sync;
grant execute on function public.feedback_pending() to feedback_sync;
grant execute on function public.feedback_mark_synced(bigint, integer) to feedback_sync;
