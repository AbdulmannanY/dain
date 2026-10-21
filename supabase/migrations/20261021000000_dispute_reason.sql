-- A dispute needs its reason (non-blank, at most 200 characters after
-- trimming), so the creator knows what to correct. The app and the share
-- page already ask for it; this makes the rule hold for anyone calling
-- respond_entry or respond_by_token directly.
--
-- Same signature as in 20261020000000_dain_core.sql, so the grants (revoked
-- from everyone) and both callers stay as they are. The state check still
-- comes first: a confirmed entry is refused with 55000 with or without a
-- reason. The note is stored trimmed, and a blank note as null.
create or replace function public._apply_response(
  p_entry public.entries, p_decision public.entry_status, p_note text, p_via text
) returns public.entry_status
language plpgsql security definer set search_path = '' as $$
declare
  v_note text := nullif(btrim(p_note), '');
begin
  if p_decision is null or p_decision not in ('confirmed', 'disputed') then
    raise exception 'decision must be confirmed or disputed' using errcode = '22023';
  end if;
  -- pending -> confirmed|disputed ; disputed -> confirmed (after the two sides settle it)
  if not (p_entry.status = 'pending' or (p_entry.status = 'disputed' and p_decision = 'confirmed')) then
    raise exception 'entry is %, cannot become %', p_entry.status, p_decision using errcode = '55000';
  end if;
  if p_decision = 'disputed' and v_note is null then
    raise exception 'a dispute needs a reason' using errcode = '22023';
  end if;
  update public.entries
     set status = p_decision, response_note = v_note, responded_at = now(), responded_via = p_via
   where id = p_entry.id;
  return p_decision;
end $$;
