-- Nightly backup support (see .github/workflows/backup.yml).
-- A read-only role that can do exactly one thing: call public.backup_export().
-- Its login password is set outside the repo and stored only as a GitHub secret.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'backup_reader') then
    create role backup_reader nologin noinherit;
  end if;
end $$;

-- Everyone's saved data, labelled with their sign-in email so it can be put back
-- into re-created accounts. Runs with the owner's rights, so backup_reader needs
-- no access to the tables themselves.
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
               ), '{}'::jsonb))
             order by u.email)
      from auth.users u
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.backup_export() from public, anon, authenticated;
grant usage on schema public to backup_reader;
grant execute on function public.backup_export() to backup_reader;
