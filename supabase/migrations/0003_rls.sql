-- Netwatch :: 0003_rls
-- Demo-friendly Row Level Security policies.
--
-- Reads: public (anon + authenticated) can SELECT from all three tables so
--        the dashboard and portfolio demo render without sign-in.
-- Writes: no policies are created. The Supabase `service_role` has BYPASSRLS,
--        so the simulator / backend scripts using the service role key
--        continue to INSERT/UPDATE freely. The anon and authenticated roles
--        are default-denied from writing -- which is what we want.
--
-- These policies are explicitly DEMO-ONLY. Before a real deployment, lock
-- reads down to authenticated users or an owning org_id.

-- RLS is already enabled by Supabase defaults, but make it explicit and
-- idempotent so this migration is self-contained.
alter table public.devices enable row level security;
alter table public.metrics enable row level security;
alter table public.alerts  enable row level security;

-- DEMO: public read access.
create policy demo_select_devices
    on public.devices
    for select
    to anon, authenticated
    using (true);

create policy demo_select_metrics
    on public.metrics
    for select
    to anon, authenticated
    using (true);

create policy demo_select_alerts
    on public.alerts
    for select
    to anon, authenticated
    using (true);
