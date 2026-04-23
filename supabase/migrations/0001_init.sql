-- Netwatch :: 0001_init
-- Initial schema: devices, metrics, alerts.
-- RLS is intentionally NOT enabled here; policies ship in a later migration.

create extension if not exists "pgcrypto";

-- Devices under monitoring.
create table if not exists public.devices (
    id           uuid primary key default gen_random_uuid(),
    hostname     text not null,
    ip_address   text not null unique,
    device_type  text not null,
    location     text,
    status       text not null default 'online',
    last_seen    timestamptz,
    created_at   timestamptz not null default now(),
    constraint devices_status_check
        check (status in ('online', 'offline', 'degraded', 'unknown'))
);

-- Append-only telemetry samples per device.
create table if not exists public.metrics (
    id               uuid primary key default gen_random_uuid(),
    device_id        uuid not null references public.devices(id) on delete cascade,
    cpu_usage        numeric(5, 2),
    memory_usage     numeric(5, 2),
    latency_ms       numeric(8, 2),
    packet_loss      numeric(5, 2),
    bandwidth_usage  numeric(10, 2),
    recorded_at      timestamptz not null default now()
);

-- Alerts raised from metrics / device state.
create table if not exists public.alerts (
    id           uuid primary key default gen_random_uuid(),
    device_id    uuid references public.devices(id) on delete cascade,
    alert_type   text not null,
    severity     text not null,
    message      text not null,
    resolved     boolean not null default false,
    created_at   timestamptz not null default now(),
    resolved_at  timestamptz,
    constraint alerts_severity_check
        check (severity in ('low', 'medium', 'high', 'critical'))
);

-- Indexes
create index if not exists idx_devices_status
    on public.devices (status);

create index if not exists idx_devices_last_seen
    on public.devices (last_seen desc);

create index if not exists idx_metrics_device_recorded
    on public.metrics (device_id, recorded_at desc);

create index if not exists idx_metrics_recorded_at
    on public.metrics (recorded_at desc);

create index if not exists idx_alerts_device
    on public.alerts (device_id);

create index if not exists idx_alerts_unresolved
    on public.alerts (created_at desc)
    where resolved = false;

create index if not exists idx_alerts_severity
    on public.alerts (severity);
