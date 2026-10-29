-- Every new signup gets the Bible lists in their Personal section (Bible 1-25 verbs and non-verbs, and the non-verb lists
-- Bible 26-50, 51-75, 76-100), the same ones current learners have. The words are kept in private.bible_seed, copied from
-- the owner's Bible lists as they are today, with their permanent progress keys. A signup can never fail because of this:
-- if seeding goes wrong, the account is still created, just without the lists. Safe to re-run; nothing existing is changed.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.bible_seed (
  seed   text not null,           -- 'bible-n-1' ...
  kind   text not null check (kind in ('verb', 'nonverb')),
  name   text not null,
  pos    int  not null,
  pkey   text not null,
  tr     text not null,
  en     text not null,
  forms  jsonb,
  primary key (seed, pkey)
);
revoke all on private.bible_seed from public, anon, authenticated;

insert into private.bible_seed (seed, kind, name, pos, pkey, tr, en, forms)
select l.seed, l.kind, l.name, t.position, t.pkey, t.tr, t.en, t.forms
from public.user_lists l
join auth.users ou on ou.id = l.user_id and ou.email = 'jacobsmethurst1@gmail.com'
join public.user_terms t on t.list_id = l.id and t.deleted_at is null
where l.seed like 'bible-%' and l.deleted_at is null
on conflict do nothing;

create or replace function private.seed_bible_lists(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  insert into public.user_lists (user_id, kind, name, seed)
  select distinct p_user, s.kind, s.name, s.seed from private.bible_seed s
  on conflict do nothing;

  insert into public.user_terms (user_id, list_id, kind, pkey, tr, en, forms, position)
  select p_user, l.id, s.kind, s.pkey, s.tr, s.en, s.forms, s.pos
  from private.bible_seed s
  join public.user_lists l on l.user_id = p_user and l.seed = s.seed
  on conflict (user_id, pkey) do nothing;
end $$;
revoke all on function private.seed_bible_lists(uuid) from public, anon, authenticated;

create or replace function private.on_new_user_seed()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  begin
    perform private.seed_bible_lists(new.id);
  exception when others then
    raise warning 'bible seeding failed for %: %', new.id, sqlerrm;   -- never block a signup
  end;
  return new;
end $$;
revoke all on function private.on_new_user_seed() from public, anon, authenticated;

drop trigger if exists seed_bible_on_signup on auth.users;
create trigger seed_bible_on_signup after insert on auth.users
  for each row execute function private.on_new_user_seed();
