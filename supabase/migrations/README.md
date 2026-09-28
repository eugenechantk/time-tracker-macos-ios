# Supabase Migrations

Apply files in filename order.

For this app, each migration should be safe to run once against the Supabase SQL editor or via the Supabase CLI. Keep schema changes here rather than editing tables manually so iOS and macOS database assumptions stay reviewable.

Current table:

- `public.time_entries`

Security note: `0001_create_time_entries.sql` preserves the app's current shared-device behavior by allowing the publishable key to read, insert, and update all rows. Before shipping this as a broader B2C app, replace these policies with authenticated user-scoped policies.
