-- An entry's day (entries.occurred_on, already grant-insertable) is picked
-- by whoever records it: a sale written down a few days late keeps its real
-- day, and the other party still confirms or disputes it. A day in the
-- future is refused. current_date is the server's (UTC) day; the app's
-- "today" runs ahead of it by up to a day (Yemen and Saudi Arabia are
-- UTC+3), so one day of slack is allowed. occurred_on is not updatable
-- (no grant, and the functions never change it), so only inserts are checked.
create function public._entries_guard_day() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.occurred_on > current_date + 1 then
    raise exception 'an entry cannot be dated in the future' using errcode = '22023';
  end if;
  return new;
end $$;

create trigger entries_guard_day before insert on public.entries
  for each row execute function public._entries_guard_day();
