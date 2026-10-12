-- "sağ ol" is now spelled "sağol". Learners' saved data is keyed by the Turkish word, so move
-- each person's existing entries to the new key. Nothing is lost: the old key is only removed
-- once its data has been copied to the new one, and only where the new key doesn't exist yet.
-- Safe to run again.

update public.user_docs
set data = jsonb_set(data #- '{words,nonverb:sağ ol}', '{words,nonverb:sağol}', data->'words'->'nonverb:sağ ol'),
    writer = 'migration',
    updated_at = now()
where doc = 'wordstats'
  and data->'words' ? 'nonverb:sağ ol'
  and not (data->'words' ? 'nonverb:sağol');

update public.user_docs
set data = jsonb_set(data #- '{known,nonverb:sağ ol}', '{known,nonverb:sağol}', data->'known'->'nonverb:sağ ol'),
    writer = 'migration',
    updated_at = now()
where doc = 'progress'
  and data->'known' ? 'nonverb:sağ ol'
  and not (data->'known' ? 'nonverb:sağol');
