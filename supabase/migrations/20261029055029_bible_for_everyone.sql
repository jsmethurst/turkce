-- Every current learner gets all of the Bible lists in their Personal section (Bible 1-25 is already everyone's).
-- The words are copied from the owner's Bible lists, keeping their permanent progress keys, so nobody's history is lost.
-- Safe to re-run: a learner who already has a list (or a word) keeps it; nothing is changed or deleted.

insert into public.user_lists (user_id, kind, name, seed)
select u.id, o.kind, o.name, o.seed
from auth.users u
cross join (
  select l.kind, l.name, l.seed
  from public.user_lists l
  join auth.users ou on ou.id = l.user_id and ou.email = 'jacobsmethurst1@gmail.com'
  where l.seed like 'bible-%' and l.deleted_at is null
) o
on conflict do nothing;

insert into public.user_terms (user_id, list_id, kind, pkey, tr, en, forms, position)
select l.user_id, l.id, t.kind, t.pkey, t.tr, t.en, t.forms, t.position
from public.user_lists l
join (
  select ol.seed, ot.kind, ot.pkey, ot.tr, ot.en, ot.forms, ot.position
  from public.user_terms ot
  join public.user_lists ol on ol.id = ot.list_id and ol.deleted_at is null and ol.seed like 'bible-%'
  join auth.users ou on ou.id = ol.user_id and ou.email = 'jacobsmethurst1@gmail.com'
  where ot.deleted_at is null
) t on t.seed = l.seed
where l.seed like 'bible-%' and l.deleted_at is null
on conflict (user_id, pkey) do nothing;
