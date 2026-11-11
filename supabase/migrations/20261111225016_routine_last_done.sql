-- Each routine remembers when it was last done. Occasional tasks ("every 30 days") are scheduled from this,
-- so a sitter who can't see older history still gets the right due date.

alter table public.routines add column last_done date;

create or replace function private.set_routine_last_done() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.last_done := (select max(l.scheduled_for) from public.care_logs l where l.routine_id = new.id and l.status = 'done');
  return new;
end $$;

create trigger routines_last_done before insert or update on public.routines
  for each row execute function private.set_routine_last_done();

create or replace function private.touch_routine_from_log() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op in ('INSERT', 'UPDATE') and new.routine_id is not null then
    update public.routines set last_done = null where id = new.routine_id;
  end if;
  if tg_op in ('DELETE', 'UPDATE') and old.routine_id is not null
     and (tg_op = 'DELETE' or old.routine_id is distinct from new.routine_id) then
    update public.routines set last_done = null where id = old.routine_id;
  end if;
  return null;
end $$;

create trigger care_logs_touch_routine after insert or update or delete on public.care_logs
  for each row execute function private.touch_routine_from_log();

update public.routines set last_done = null;
