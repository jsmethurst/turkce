-- "Suggest a change": the feedback button can now attach a screenshot of part of the page.
-- It's stored as a data: URL (PNG or JPEG, under 1,000,000 characters). The sync workflow
-- copies it to the repo's feedback-screenshots branch and shows it in the GitHub issue.
-- Bug and idea are no longer distinguished; new rows keep the column's default.

alter table public.feedback add column if not exists screenshot text
  check (screenshot is null or (char_length(screenshot) <= 1000000
                                and screenshot ~ '^data:image/(png|jpeg);base64,[A-Za-z0-9+/=]+$'));

grant insert (screenshot) on public.feedback to anon, authenticated;

create or replace function public.feedback_pending()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', f.id, 'created_at', f.created_at, 'kind', f.kind,
           'message', f.message, 'context', f.context, 'user_agent', f.user_agent,
           'signed_in', f.user_id is not null,
           'has_screenshot', f.screenshot is not null)
         order by f.id), '[]'::jsonb)
  from public.feedback f
  where f.issue_number is null;
$$;

create or replace function public.feedback_screenshot(p_id bigint)
returns text language sql stable security definer set search_path = '' as $$
  select f.screenshot from public.feedback f where f.id = p_id;
$$;

revoke all on function public.feedback_screenshot(bigint) from public, anon, authenticated;
grant execute on function public.feedback_screenshot(bigint) to feedback_sync;
