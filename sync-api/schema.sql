-- TimeTracker sync schema (Neon). Apply once: psql "$DATABASE_URL" -f schema.sql
-- Times are Unix epoch seconds (double precision), matching the app's timeIntervalSince1970.
create table if not exists time_entries (
  device_entry_id   text primary key,
  slot_start        double precision not null,
  slot_end          double precision not null,
  entry_description text not null,
  submitted_at      double precision not null
);

create index if not exists time_entries_slot_start_idx on time_entries (slot_start);
