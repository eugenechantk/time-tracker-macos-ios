alter table public.time_entries
  add column if not exists slot_end double precision;

update public.time_entries
set slot_end = slot_start + 1800
where slot_end is null;

alter table public.time_entries
  alter column slot_end set not null;

create index if not exists time_entries_slot_end_idx
  on public.time_entries (slot_end);
