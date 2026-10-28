-- Personal word lists. Each learner has their own lists and terms (editable in the app); the built-in A1 lists stay in the page.
-- Every term has an id and a permanent progress key (pkey). Learners' saved progress (word_stats) is keyed by pkey,
-- so the Turkish and the English can be edited without losing it. Terms and lists are never really deleted:
-- deleting sets deleted_at, so a mistake can be undone. Safe to re-run; nothing existing is changed or deleted.

-- ---------- lists ----------
create table if not exists public.user_lists (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users on delete cascade,
  kind       text not null check (kind in ('verb', 'nonverb')),
  name       text not null check (char_length(btrim(name)) between 1 and 80),
  seed       text,                                  -- which starter list this came from (so seeding never repeats)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists user_lists_user_idx on public.user_lists (user_id);
create unique index if not exists user_lists_seed_idx on public.user_lists (user_id, seed) where seed is not null;

-- ---------- terms ----------
create table if not exists public.user_terms (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users on delete cascade,
  list_id    uuid not null references public.user_lists on delete cascade,
  kind       text not null check (kind in ('verb', 'nonverb')),
  pkey       text not null check (pkey ~ '^(verb|nonverb):.{1,90}$'),   -- permanent: the key progress is saved under (a trigger fills it in for new terms)
  tr         text not null check (char_length(btrim(tr)) between 1 and 100),
  en         text not null check (char_length(btrim(en)) between 1 and 300),
  forms      jsonb check (forms is null or (jsonb_typeof(forms) = 'object' and pg_column_size(forms) <= 6000)),   -- verbs: English forms + example
  position   int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, pkey)
);
create index if not exists user_terms_user_list_idx on public.user_terms (user_id, list_id);

-- ---------- rules: a learner sees and changes only their own rows; rows are never really deleted ----------
alter table public.user_lists enable row level security;
alter table public.user_terms enable row level security;
do $$
declare t text;
begin
  foreach t in array array['user_lists', 'user_terms'] loop
    execute format('drop policy if exists "own rows: read" on public.%I', t);
    execute format('drop policy if exists "own rows: insert" on public.%I', t);
    execute format('drop policy if exists "own rows: update" on public.%I', t);
    execute format('create policy "own rows: read" on public.%I for select to authenticated using (user_id = (select auth.uid()))', t);
    execute format('create policy "own rows: insert" on public.%I for insert to authenticated with check (user_id = (select auth.uid()))', t);
    execute format('create policy "own rows: update" on public.%I for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);
  end loop;
end $$;
revoke all on public.user_lists, public.user_terms from anon, authenticated;
grant select, insert, update on public.user_lists, public.user_terms to authenticated;

-- ---------- checks and housekeeping ----------
create or replace function public.user_lists_guard()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    if (select count(*) from public.user_lists where user_id = new.user_id and deleted_at is null) >= 200 then
      raise exception 'too many lists (limit 200)';
    end if;
  else
    if new.user_id <> old.user_id or new.kind <> old.kind then raise exception 'a list''s owner and kind cannot change'; end if;
    new.updated_at := now();
  end if;
  return new;
end $$;
drop trigger if exists user_lists_guard on public.user_lists;
create trigger user_lists_guard before insert or update on public.user_lists for each row execute function public.user_lists_guard();

create or replace function public.user_terms_guard()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    if new.pkey is null or new.pkey = '' then
      new.pkey := new.kind || ':u_' || substr(replace(new.id::text, '-', ''), 1, 12);
    end if;
    if (select count(*) from public.user_terms where user_id = new.user_id and deleted_at is null) >= 5000 then
      raise exception 'too many terms (limit 5000)';
    end if;
  else
    if new.pkey <> old.pkey or new.id <> old.id or new.user_id <> old.user_id or new.kind <> old.kind then
      raise exception 'a term''s id, owner, kind and progress key cannot change';
    end if;
    new.updated_at := now();
  end if;
  if not exists (select 1 from public.user_lists l where l.id = new.list_id and l.user_id = new.user_id and l.kind = new.kind) then
    raise exception 'the list must be yours and of the same kind (verb / non-verb)';
  end if;
  return new;
end $$;
drop trigger if exists user_terms_guard on public.user_terms;
create trigger user_terms_guard before insert or update on public.user_terms for each row execute function public.user_terms_guard();

-- ---------- starter lists: every current learner gets "Bible 1-25" (verbs and non-verbs) ----------
-- Terms keep their old progress keys, so nobody loses history. The owner's remaining Bible lists are kept too.
create temp table _seed (seed text, kind text, pos int, pkey text, tr text, en text, forms jsonb) on commit drop;
insert into _seed values
  ('bible-n-1', 'nonverb', 0, 'nonverb:RAB', 'RAB', 'the LORD (YHWH)', null),
  ('bible-n-1', 'nonverb', 1, 'nonverb:tanrı', 'tanrı', 'God', null),
  ('bible-n-1', 'nonverb', 2, 'nonverb:İsa', 'İsa', 'Jesus', null),
  ('bible-n-1', 'nonverb', 3, 'nonverb:kutsal', 'kutsal', 'holy', null),
  ('bible-n-1', 'nonverb', 4, 'nonverb:iblis', 'iblis', 'the devil', null),
  ('bible-n-1', 'nonverb', 5, 'nonverb:yürek', 'yürek', 'heart', null),
  ('bible-n-1', 'nonverb', 6, 'nonverb:günah', 'günah', 'sin', null),
  ('bible-n-1', 'nonverb', 7, 'nonverb:ruh', 'ruh', 'spirit / Spirit', null),
  ('bible-n-1', 'nonverb', 8, 'nonverb:kötülük', 'kötülük', 'evil / wickedness', null),
  ('bible-n-1', 'nonverb', 9, 'nonverb:gök', 'gök', 'sky / heaven', null),
  ('bible-n-1', 'nonverb', 10, 'nonverb:Mesih', 'Mesih', 'Christ / Messiah', null),
  ('bible-n-1', 'nonverb', 11, 'nonverb:can', 'can', 'soul / life', null),
  ('bible-n-1', 'nonverb', 12, 'nonverb:gerçek', 'gerçek', 'truth / real', null),
  ('bible-n-1', 'nonverb', 13, 'nonverb:krallık', 'krallık', 'kingdom', null),
  ('bible-n-1', 'nonverb', 14, 'nonverb:iman', 'iman', 'faith', null),
  ('bible-n-1', 'nonverb', 15, 'nonverb:yasa', 'yasa', 'law', null),
  ('bible-n-1', 'nonverb', 16, 'nonverb:yücelik', 'yücelik', 'glory / majesty', null),
  ('bible-n-1', 'nonverb', 17, 'nonverb:buyruk', 'buyruk', 'command / decree', null),
  ('bible-n-1', 'nonverb', 18, 'nonverb:sonsuz', 'sonsuz', 'eternal / endless', null),
  ('bible-n-1', 'nonverb', 19, 'nonverb:antlaşma', 'antlaşma', 'covenant', null),
  ('bible-n-1', 'nonverb', 20, 'nonverb:suç', 'suç', 'guilt / crime / offense', null),
  ('bible-n-1', 'nonverb', 21, 'nonverb:sevgi', 'sevgi', 'love', null),
  ('bible-n-1', 'nonverb', 22, 'nonverb:hak', 'hak', 'right / justice / due', null),
  ('bible-n-1', 'nonverb', 23, 'nonverb:elçi', 'elçi', 'apostle / messenger', null),
  ('bible-n-1', 'nonverb', 24, 'nonverb:ölüm', 'ölüm', 'death', null),
  ('bible-n-2', 'nonverb', 0, 'nonverb:doğruluk', 'doğruluk', 'righteousness', null),
  ('bible-n-2', 'nonverb', 1, 'nonverb:esenlik', 'esenlik', 'peace / well-being', null),
  ('bible-n-2', 'nonverb', 2, 'nonverb:hüküm', 'hüküm', 'judgment / decree / rule', null),
  ('bible-n-2', 'nonverb', 3, 'nonverb:öfke', 'öfke', 'anger / wrath', null),
  ('bible-n-2', 'nonverb', 4, 'nonverb:ant', 'ant', 'oath', null),
  ('bible-n-2', 'nonverb', 5, 'nonverb:oruç', 'oruç', 'fasting / fast', null),
  ('bible-n-2', 'nonverb', 6, 'nonverb:merhamet', 'merhamet', 'mercy / compassion', null),
  ('bible-n-2', 'nonverb', 7, 'nonverb:ışık', 'ışık', 'light', null),
  ('bible-n-2', 'nonverb', 8, 'nonverb:lütuf', 'lütuf', 'grace / favor', null),
  ('bible-n-2', 'nonverb', 9, 'nonverb:taht', 'taht', 'throne', null),
  ('bible-n-2', 'nonverb', 10, 'nonverb:karanlık', 'karanlık', 'darkness', null),
  ('bible-n-2', 'nonverb', 11, 'nonverb:yargı', 'yargı', 'judgment', null),
  ('bible-n-2', 'nonverb', 12, 'nonverb:görkem', 'görkem', 'splendor / magnificence', null),
  ('bible-n-2', 'nonverb', 13, 'nonverb:lanet', 'lanet', 'curse', null),
  ('bible-n-2', 'nonverb', 14, 'nonverb:gazap', 'gazap', 'wrath', null),
  ('bible-n-2', 'nonverb', 15, 'nonverb:duyunç', 'duyunç', 'conscience (biblical)', null),
  ('bible-n-2', 'nonverb', 16, 'nonverb:kurtuluş', 'kurtuluş', 'salvation / deliverance', null),
  ('bible-n-2', 'nonverb', 17, 'nonverb:itaat', 'itaat', 'obedience', null),
  ('bible-n-2', 'nonverb', 18, 'nonverb:umut', 'umut', 'hope', null),
  ('bible-n-2', 'nonverb', 19, 'nonverb:müjde', 'müjde', 'good news / gospel', null),
  ('bible-n-2', 'nonverb', 20, 'nonverb:kefaret', 'kefaret', 'atonement', null),
  ('bible-n-2', 'nonverb', 21, 'nonverb:günahkâr', 'günahkâr', 'sinner / sinful', null),
  ('bible-n-2', 'nonverb', 22, 'nonverb:vaat', 'vaat', 'promise', null),
  ('bible-n-2', 'nonverb', 23, 'nonverb:tövbe', 'tövbe', 'repentance', null),
  ('bible-n-2', 'nonverb', 24, 'nonverb:sadakat', 'sadakat', 'faithfulness / loyalty', null),
  ('bible-n-3', 'nonverb', 0, 'nonverb:kurtarıcı', 'kurtarıcı', 'savior / deliverer', null),
  ('bible-n-3', 'nonverb', 1, 'nonverb:din', 'din', 'religion / faith', null),
  ('bible-n-3', 'nonverb', 2, 'nonverb:fidye', 'fidye', 'ransom', null),
  ('bible-n-3', 'nonverb', 3, 'nonverb:bereket', 'bereket', 'blessing / abundance', null),
  ('bible-n-3', 'nonverb', 4, 'nonverb:sır', 'sır', 'secret / mystery', null),
  ('bible-n-3', 'nonverb', 5, 'nonverb:diriliş', 'diriliş', 'resurrection', null),
  ('bible-n-3', 'nonverb', 6, 'nonverb:vicdan', 'vicdan', 'conscience', null),
  ('bible-n-3', 'nonverb', 7, 'nonverb:ebedî', 'ebedî', 'eternal / everlasting', null),
  ('bible-n-3', 'nonverb', 8, 'nonverb:kul', 'kul', 'servant / bondservant', null),
  ('bible-n-3', 'nonverb', 9, 'nonverb:inanç', 'inanç', 'belief / faith', null),
  ('bible-n-3', 'nonverb', 10, 'nonverb:kutsallık', 'kutsallık', 'holiness', null),
  ('bible-n-3', 'nonverb', 11, 'nonverb:vahiy', 'vahiy', 'revelation', null),
  ('bible-n-3', 'nonverb', 12, 'nonverb:cennet', 'cennet', 'paradise / heaven', null),
  ('bible-n-3', 'nonverb', 13, 'nonverb:gizem', 'gizem', 'mystery', null),
  ('bible-n-3', 'nonverb', 14, 'nonverb:yaşam', 'yaşam', 'life', null),
  ('bible-n-3', 'nonverb', 15, 'nonverb:söz', 'söz', 'word / saying', null),
  ('bible-n-3', 'nonverb', 16, 'nonverb:sunu', 'sunu', 'offering', null),
  ('bible-n-3', 'nonverb', 17, 'nonverb:kâhin', 'kâhin', 'priest', null),
  ('bible-n-3', 'nonverb', 18, 'nonverb:peygamber', 'peygamber', 'prophet', null),
  ('bible-n-3', 'nonverb', 19, 'nonverb:sunak', 'sunak', 'altar', null),
  ('bible-n-3', 'nonverb', 20, 'nonverb:çadır', 'çadır', 'tent / tabernacle', null),
  ('bible-n-3', 'nonverb', 21, 'nonverb:topluluk', 'topluluk', 'assembly / congregation', null),
  ('bible-n-3', 'nonverb', 22, 'nonverb:kurban', 'kurban', 'sacrifice / offering', null),
  ('bible-n-3', 'nonverb', 23, 'nonverb:dua', 'dua', 'prayer', null),
  ('bible-n-3', 'nonverb', 24, 'nonverb:ilâh', 'ilâh', 'god (deity) / idol', null),
  ('bible-n-4', 'nonverb', 0, 'nonverb:Üçlü Birlik', 'Üçlü Birlik', 'Trinity (triple unity)', null),
  ('bible-n-4', 'nonverb', 1, 'nonverb:melek', 'melek', 'angel', null),
  ('bible-n-4', 'nonverb', 2, 'nonverb:tapınak', 'tapınak', 'temple', null),
  ('bible-n-4', 'nonverb', 3, 'nonverb:miras', 'miras', 'inheritance', null),
  ('bible-n-4', 'nonverb', 4, 'nonverb:tanıklık', 'tanıklık', 'testimony / witness', null),
  ('bible-n-4', 'nonverb', 5, 'nonverb:bilgelik', 'bilgelik', 'wisdom', null),
  ('bible-n-4', 'nonverb', 6, 'nonverb:sandık', 'sandık', 'chest / ark', null),
  ('bible-n-4', 'nonverb', 7, 'nonverb:sürü', 'sürü', 'flock / herd', null),
  ('bible-n-4', 'nonverb', 8, 'nonverb:kuzu', 'kuzu', 'lamb', null),
  ('bible-n-4', 'nonverb', 9, 'nonverb:bilge', 'bilge', 'wise / a wise person', null),
  ('bible-n-4', 'nonverb', 10, 'nonverb:iğrenç', 'iğrenç', 'detestable / abominable', null),
  ('bible-n-4', 'nonverb', 11, 'nonverb:peygamberlik', 'peygamberlik', 'prophecy', null),
  ('bible-n-4', 'nonverb', 12, 'nonverb:sürgün', 'sürgün', 'exile', null),
  ('bible-n-4', 'nonverb', 13, 'nonverb:Şabat', 'Şabat', 'Sabbath', null),
  ('bible-n-4', 'nonverb', 14, 'nonverb:kusur', 'kusur', 'fault / defect / blemish', null),
  ('bible-n-4', 'nonverb', 15, 'nonverb:put', 'put', 'idol', null),
  ('bible-n-4', 'nonverb', 16, 'nonverb:sünnet', 'sünnet', 'circumcision', null),
  ('bible-n-4', 'nonverb', 17, 'nonverb:belirti', 'belirti', 'sign', null),
  ('bible-n-4', 'nonverb', 18, 'nonverb:buhur', 'buhur', 'incense', null),
  ('bible-n-4', 'nonverb', 19, 'nonverb:konut', 'konut', 'dwelling / tabernacle', null),
  ('bible-n-4', 'nonverb', 20, 'nonverb:bayram', 'bayram', 'feast / festival', null),
  ('bible-n-4', 'nonverb', 21, 'nonverb:övgü', 'övgü', 'praise', null),
  ('bible-n-4', 'nonverb', 22, 'nonverb:çarmıh', 'çarmıh', 'cross', null),
  ('bible-n-4', 'nonverb', 23, 'nonverb:kilise', 'kilise', 'church', null),
  ('bible-n-4', 'nonverb', 24, 'nonverb:şeytan', 'şeytan', 'Satan', null),
  ('bible-v-1', 'verb', 0, 'verb:kurtarmak', 'kurtarmak', 'to save / to deliver / to rescue', '{"base": "save / deliver / rescue", "ing": "saving / delivering / rescuing", "past": "saved / delivered / rescued", "pp": "saved / delivered / rescued", "gloss": "to save / to deliver / to rescue", "cases": [{"c": "akuzatif", "en": "God is saving us.", "ex": "Tanrı biz<b>i</b> kurtarıyor."}]}'::jsonb),
  ('bible-v-1', 'verb', 1, 'verb:kutsamak', 'kutsamak', 'to bless', '{"base": "bless", "ing": "blessing", "past": "blessed", "pp": "blessed", "gloss": "to bless", "cases": [{"c": "akuzatif", "en": "May the LORD bless you.", "ex": "RAB sen<b>i</b> kutsasın."}]}'::jsonb),
  ('bible-v-1', 'verb', 2, 'verb:kurtulmak', 'kurtulmak', 'to be saved / to be freed', '{"base": "be saved / be freed", "ing": "being saved / being freed", "past": "was saved / was freed", "pp": "been saved / been freed", "gloss": "to be saved / to be freed", "cases": [{"c": "ablatif", "en": "We were saved from sin.", "ex": "Günah<b>tan</b> kurtulduk."}]}'::jsonb),
  ('bible-v-1', 'verb', 3, 'verb:bağışlamak', 'bağışlamak', 'to forgive / to grant', '{"base": "forgive / grant", "ing": "forgiving / granting", "past": "forgave / granted", "pp": "forgiven / granted", "gloss": "to forgive / to grant", "cases": [{"c": "akuzatif", "en": "God forgives our sins.", "ex": "Tanrı günahlarımız<b>ı</b> bağışlıyor."}]}'::jsonb),
  ('bible-v-1', 'verb', 4, 'verb:sapmak', 'sapmak', 'to turn aside / to stray', '{"base": "turn aside / stray", "ing": "turning aside / straying", "past": "turned aside / strayed", "pp": "turned aside / strayed", "gloss": "to turn aside / to stray", "cases": [{"c": "ablatif", "en": "Don''t stray from the right path.", "ex": "Doğru yol<b>dan</b> sapmayın."}]}'::jsonb),
  ('bible-v-1', 'verb', 5, 'verb:dirilmek', 'dirilmek', 'to rise from the dead', '{"base": "rise from the dead", "ing": "rising from the dead", "past": "rose from the dead", "pp": "risen from the dead", "gloss": "to rise from the dead", "cases": [{"c": "ablatif", "en": "Jesus rose from the dead.", "ex": "İsa ölüler<b>den</b> dirildi."}]}'::jsonb),
  ('bible-v-1', 'verb', 6, 'verb:kirletmek', 'kirletmek', 'to defile / to make unclean', '{"base": "defile / make unclean", "ing": "defiling / making unclean", "past": "defiled / made unclean", "pp": "defiled / made unclean", "gloss": "to defile / to make unclean", "cases": [{"c": "akuzatif", "en": "They defiled the temple.", "ex": "Tapınağ<b>ı</b> kirlettiler."}]}'::jsonb),
  ('bible-v-1', 'verb', 7, 'verb:yükselmek', 'yükselmek', 'to rise / to ascend', '{"base": "rise / ascend", "ing": "rising / ascending", "past": "rose / ascended", "pp": "risen / ascended", "gloss": "to rise / to ascend", "cases": [{"c": "datif", "en": "Jesus ascended to heaven.", "ex": "İsa göğ<b>e</b> yükseldi."}]}'::jsonb),
  ('bible-v-1', 'verb', 8, 'verb:tapınmak', 'tapınmak', 'to worship (God)', '{"base": "worship (God)", "ing": "worshiping (God)", "past": "worshiped (God)", "pp": "worshiped (God)", "gloss": "to worship (God)", "cases": [{"c": "datif", "en": "We worship only God.", "ex": "Yalnız Tanrı''<b>ya</b> tapınıyoruz."}]}'::jsonb),
  ('bible-v-1', 'verb', 9, 'verb:yaratmak', 'yaratmak', 'to create', '{"base": "create", "ing": "creating", "past": "created", "pp": "created", "gloss": "to create", "cases": [{"c": "akuzatif", "en": "God created the heavens and the earth.", "ex": "Tanrı gökler<b>i</b> ve yer<b>i</b> yarattı."}]}'::jsonb),
  ('bible-v-1', 'verb', 10, 'verb:yargılamak', 'yargılamak', 'to judge', '{"base": "judge", "ing": "judging", "past": "judged", "pp": "judged", "gloss": "to judge", "cases": [{"c": "akuzatif", "en": "God will judge the world.", "ex": "Tanrı dünya<b>yı</b> yargılayacak."}]}'::jsonb),
  ('bible-v-1', 'verb', 11, 'verb:övmek', 'övmek', 'to praise', '{"base": "praise", "ing": "praising", "past": "praised", "pp": "praised", "gloss": "to praise", "cases": [{"c": "akuzatif", "en": "We praise the LORD.", "ex": "RAB''b<b>i</b> övüyoruz."}]}'::jsonb),
  ('bible-v-1', 'verb', 12, 'verb:meshetmek', 'meshetmek', 'to anoint', '{"base": "anoint", "ing": "anointing", "past": "anointed", "pp": "anointed", "gloss": "to anoint", "cases": [{"c": "akuzatif", "en": "The prophet anointed the king.", "ex": "Peygamber kral<b>ı</b> meshetti."}]}'::jsonb),
  ('bible-v-1', 'verb', 13, 'verb:adamak', 'adamak', 'to dedicate / to vow', '{"base": "dedicate / vow", "ing": "dedicating / vowing", "past": "dedicated / vowed", "pp": "dedicated / vowed", "gloss": "to dedicate / to vow", "cases": [{"c": "datif", "en": "I''m dedicating my life to God.", "ex": "Hayatımı Tanrı''<b>ya</b> adıyorum."}]}'::jsonb),
  ('bible-v-1', 'verb', 14, 'verb:arınmak', 'arınmak', 'to be cleansed / to be purified', '{"base": "be cleansed / be purified", "ing": "being cleansed / being purified", "past": "was cleansed / was purified", "pp": "been cleansed / been purified", "gloss": "to be cleansed / to be purified", "cases": [{"c": "ablatif", "en": "We are being cleansed of our sins.", "ex": "Günahlarımız<b>dan</b> arınıyoruz."}]}'::jsonb),
  ('bible-v-1', 'verb', 15, 'verb:alçaltmak', 'alçaltmak', 'to humble / to lower', '{"base": "humble / lower", "ing": "humbling / lowering", "past": "humbled / lowered", "pp": "humbled / lowered", "gloss": "to humble / to lower", "cases": [{"c": "akuzatif", "en": "God humbles the proud.", "ex": "Tanrı gururlular<b>ı</b> alçaltır."}]}'::jsonb),
  ('bible-v-1', 'verb', 16, 'verb:suçlamak', 'suçlamak', 'to accuse / to blame', '{"base": "accuse / blame", "ing": "accusing / blaming", "past": "accused / blamed", "pp": "accused / blamed", "gloss": "to accuse / to blame", "cases": [{"c": "akuzatif", "en": "They are accusing me.", "ex": "Onlar ben<b>i</b> suçluyor."}]}'::jsonb),
  ('bible-v-1', 'verb', 17, 'verb:tapmak', 'tapmak', 'to worship (idols) / to adore', '{"base": "worship (idols) / adore", "ing": "worshiping (idols) / adoring", "past": "worshiped (idols) / adored", "pp": "worshiped (idols) / adored", "gloss": "to worship (idols) / to adore", "cases": [{"c": "datif", "en": "Do not worship idols.", "ex": "Putlar<b>a</b> tapmayın."}]}'::jsonb),
  ('bible-v-1', 'verb', 18, 'verb:küfretmek', 'küfretmek', 'to curse / to blaspheme', '{"base": "curse / blaspheme", "ing": "cursing / blaspheming", "past": "cursed / blasphemed", "pp": "cursed / blasphemed", "gloss": "to curse / to blaspheme", "cases": [{"c": "datif", "en": "Do not blaspheme God.", "ex": "Tanrı''<b>ya</b> küfretmeyin."}]}'::jsonb),
  ('bible-v-1', 'verb', 19, 'verb:lanetlemek', 'lanetlemek', 'to curse', '{"base": "curse", "ing": "cursing", "past": "cursed", "pp": "cursed", "gloss": "to curse", "cases": [{"c": "akuzatif", "en": "God cursed the serpent.", "ex": "Tanrı yılan<b>ı</b> lanetledi."}]}'::jsonb),
  ('bible-v-1', 'verb', 20, 'verb:kirlenmek', 'kirlenmek', 'to become unclean / to be defiled', '{"base": "become unclean / be defiled", "ing": "becoming unclean / being defiled", "past": "became unclean / was defiled", "pp": "become unclean / been defiled", "gloss": "to become unclean / to be defiled", "cases": [{"c": "örnek", "en": "The vessel became unclean.", "ex": "Kap kirlendi."}]}'::jsonb),
  ('bible-v-1', 'verb', 21, 'verb:aldatmak', 'aldatmak', 'to deceive', '{"base": "deceive", "ing": "deceiving", "past": "deceived", "pp": "deceived", "gloss": "to deceive", "cases": [{"c": "akuzatif", "en": "The serpent deceived the woman.", "ex": "Yılan kadın<b>ı</b> aldattı."}]}'::jsonb),
  ('bible-v-1', 'verb', 22, 'verb:şükretmek', 'şükretmek', 'to give thanks', '{"base": "give thanks", "ing": "giving thanks", "past": "gave thanks", "pp": "given thanks", "gloss": "to give thanks", "cases": [{"c": "datif", "en": "We give thanks to God.", "ex": "Tanrı''<b>ya</b> şükrediyoruz."}]}'::jsonb),
  ('bible-v-1', 'verb', 23, 'verb:aklanmak', 'aklanmak', 'to be justified', '{"base": "be justified", "ing": "being justified", "past": "was justified", "pp": "been justified", "gloss": "to be justified", "cases": [{"c": "ile", "en": "We are justified by faith.", "ex": "İman<b>la</b> aklanıyoruz."}]}'::jsonb),
  ('bible-v-1', 'verb', 24, 'verb:aklamak', 'aklamak', 'to justify / to acquit', '{"base": "justify / acquit", "ing": "justifying / acquitting", "past": "justified / acquitted", "pp": "justified / acquitted", "gloss": "to justify / to acquit", "cases": [{"c": "akuzatif", "en": "God justifies the believer.", "ex": "Tanrı imanlı<b>yı</b> aklar."}]}'::jsonb);

insert into public.user_lists (user_id, kind, name, seed)
select u.id, s.kind, 'Bible ' || ((s.n - 1) * 25 + 1) || '-' || ((s.n - 1) * 25 + s.cnt), s.seed
from auth.users u
cross join (
  select seed, kind, split_part(seed, '-', 3)::int as n, count(*)::int as cnt from _seed group by seed, kind
) s
where (s.seed in ('bible-n-1', 'bible-v-1') or u.email = 'jacobsmethurst1@gmail.com')
on conflict do nothing;

insert into public.user_terms (user_id, list_id, kind, pkey, tr, en, forms, position)
select l.user_id, l.id, s.kind, s.pkey, s.tr, s.en, s.forms, s.pos
from public.user_lists l
join _seed s on s.seed = l.seed
on conflict (user_id, pkey) do nothing;

-- ---------- the nightly backup includes the new tables ----------
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
               ), '[]'::jsonb),
               'lists', coalesce((
                 select jsonb_agg(to_jsonb(l) - 'user_id' order by l.created_at, l.id)
                 from public.user_lists l
                 where l.user_id = u.id
               ), '[]'::jsonb),
               'terms', coalesce((
                 select jsonb_agg(to_jsonb(t) - 'user_id' order by t.list_id, t.position, t.id)
                 from public.user_terms t
                 where t.user_id = u.id
               ), '[]'::jsonb))
             order by u.email)
      from auth.users u
    ), '[]'::jsonb)
  );
$$;
