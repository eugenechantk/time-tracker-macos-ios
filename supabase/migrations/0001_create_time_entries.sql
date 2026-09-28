create table if not exists public.time_entries (
  device_entry_id text primary key,
  slot_start double precision not null,
  entry_description text not null,
  submitted_at double precision not null
);

create index if not exists time_entries_slot_start_idx
  on public.time_entries (slot_start);

create index if not exists time_entries_submitted_at_idx
  on public.time_entries (submitted_at desc);

alter table public.time_entries enable row level security;

create policy "Allow publishable key reads"
  on public.time_entries
  for select
  to anon
  using (true);

create policy "Allow publishable key inserts"
  on public.time_entries
  for insert
  to anon
  with check (true);

create policy "Allow publishable key updates"
  on public.time_entries
  for update
  to anon
  using (true)
  with check (true);

alter publication supabase_realtime
  add table public.time_entries;
