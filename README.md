# Netwatch

A lightweight, SOC-style network monitoring and alerting system built on Supabase.

Netwatch tracks devices, ingests telemetry (CPU, memory, latency, packet loss, bandwidth), and raises alerts when thresholds are breached or a device goes silent. The design goal is to demonstrate real backend fundamentals — schema design, Row Level Security, trigger-driven alerting, idempotent seeding — in a system small enough to read end-to-end in an afternoon.

## Features

- Typed Postgres schema for devices, metrics, and alerts (UUID PKs, CHECK constraints, partial indexes).
- Demo-friendly Row Level Security: public read, service-role writes only.
- Threshold-based alert generation entirely inside Postgres — no extra workers to operate.
- Offline detection via a callable SQL function; trivially promotable to `pg_cron`.
- Idempotent seed script and a TypeScript simulator that publishes fake telemetry.
- Clean SQL migrations under `supabase/migrations/`.

## Architecture

```
┌──────────────┐   insert metrics    ┌──────────────────────────────┐
│  Simulator   │ ──────────────────▶ │  Supabase Postgres           │
│  (Node/TS)   │                     │                              │
└──────────────┘                     │  devices   metrics   alerts  │
        │                            │                              │
        │  rpc('netwatch_            │  AFTER INSERT ON metrics →   │
        │   detect_offline')         │  evaluate thresholds,        │
        └──────────────────────────▶ │  open/close alert rows,      │
                                     │  bump device last_seen.      │
                                     └──────────────┬───────────────┘
                                                    │ Realtime
                                                    ▼
                                     ┌──────────────────────────────┐
                                     │  Dashboard (planned)         │
                                     │  React + Supabase client     │
                                     └──────────────────────────────┘
```

The database is the brain. The simulator is the only thing writing, and it only writes through the service role. A future dashboard reads through the anon key and subscribes to changes via Supabase Realtime.

## Data model

### `devices`
One row per monitored host.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `hostname` | `text` | not null |
| `ip_address` | `text` | not null, unique |
| `device_type` | `text` | e.g. `router`, `firewall`, `switch`, `server`, `access_point` |
| `location` | `text` | nullable |
| `status` | `text` | CHECK in `('online','offline','degraded','unknown')`, default `online` |
| `last_seen` | `timestamptz` | updated by the metric trigger |
| `created_at` | `timestamptz` | default `now()` |

### `metrics`
Append-only telemetry samples.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `uuid` | PK |
| `device_id` | `uuid` | FK → `devices(id)` ON DELETE CASCADE |
| `cpu_usage` | `numeric(5,2)` | percent, 0–100 |
| `memory_usage` | `numeric(5,2)` | percent, 0–100 |
| `latency_ms` | `numeric(8,2)` | non-negative |
| `packet_loss` | `numeric(5,2)` | percent, 0–100 |
| `bandwidth_usage` | `numeric(10,2)` | non-negative |
| `recorded_at` | `timestamptz` | default `now()` |

Indexed on `(device_id, recorded_at desc)` for fast per-device recent-reads and on `recorded_at desc` for global timeline views.

### `alerts`
Opened by triggers, closed automatically when the condition clears.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `uuid` | PK |
| `device_id` | `uuid` | FK → `devices(id)` ON DELETE CASCADE |
| `alert_type` | `text` | e.g. `high_cpu`, `device_offline` |
| `severity` | `text` | CHECK in `('low','medium','high','critical')` |
| `message` | `text` | human-readable summary |
| `resolved` | `boolean` | default `false` |
| `created_at` | `timestamptz` | default `now()` |
| `resolved_at` | `timestamptz` | set when auto-resolved |

Partial index on `created_at desc WHERE resolved = false` keeps the common "show me open alerts" query fast.

## Alert rules

| `alert_type` | `severity` | Condition |
| --- | --- | --- |
| `high_cpu` | high | `cpu_usage >= 90` |
| `high_memory` | high | `memory_usage >= 90` |
| `latency_spike` | medium | `latency_ms >= 250` |
| `high_packet_loss` | medium | `packet_loss >= 5` |
| `device_offline` | critical | `last_seen` older than 2 minutes |

Metric alerts fire from an `AFTER INSERT` trigger on `metrics`. If the condition is breached and no open alert of that type exists, one is opened. When a subsequent metric clears the condition, the open alert is auto-resolved. Offline detection runs from `netwatch_detect_offline()`, which the simulator calls on every tick and which can later be scheduled with `pg_cron`.

## Project structure

```
.
├── supabase/migrations/   Versioned SQL migrations
├── scripts/               Seed data, telemetry simulator
├── src/lib/               Supabase client + shared types and fixtures
├── docs/                  Architecture notes
├── .env.example
├── package.json
└── tsconfig.json
```

## Migrations

| File | Purpose |
| --- | --- |
| `0001_init.sql` | Core schema, indexes, status/severity CHECKs |
| `0002_metric_ranges.sql` | Data-quality CHECKs on metric columns (0–100%, non-negative) |
| `0003_rls.sql` | Enables RLS; demo-only public SELECT policies |
| `0004_alerts.sql` | `netwatch_upsert_alert`, `netwatch_evaluate_metric` trigger, `netwatch_detect_offline` |

Apply them in order via the Supabase SQL editor, the Supabase CLI, or the MCP server during development.

## Quick start

### Prerequisites

- Node.js 20+
- A Supabase project (free tier is fine)

### Setup

```bash
cp .env.example .env
# Fill in SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
npm install
```

Then apply every SQL file in `supabase/migrations/` in order.

### Run

```bash
npm run seed        # idempotent: inserts/updates 7 demo devices by ip_address
npm run simulate    # every 5s: emits telemetry, occasionally injects an anomaly
```

Tune the simulator cadence with `SIMULATE_INTERVAL_MS=2000 npm run simulate`.

Watch alerts being opened and closed in real time from the Supabase dashboard or a SQL query:

```sql
select alert_type, severity, message, created_at, resolved
  from alerts
 order by created_at desc
 limit 20;
```

## Environment variables

| Variable | Purpose |
| --- | --- |
| `SUPABASE_URL` | Project URL |
| `SUPABASE_ANON_KEY` | Public anon key (read-only demo access) |
| `SUPABASE_SERVICE_ROLE_KEY` | Server-side writes (simulator, seed) — never ship to a client |
| `SIMULATE_INTERVAL_MS` | Optional simulator tick (default `5000`) |

The service role key lives in **Project Settings → API → `service_role` secret** in the Supabase dashboard. It is ignored by `.gitignore` as part of `.env`.

## Security posture

- Row Level Security is on for every table.
- Policies shipped today are `demo_select_*` — public SELECT on `devices`, `metrics`, `alerts`. They exist so the dashboard can render without auth.
- No write policies exist for `anon` or `authenticated`, so only the `service_role` (which has `BYPASSRLS`) can write.
- All trigger functions are `SECURITY DEFINER` with an explicit `search_path = public` to satisfy the Supabase security linter.
- Before a real deployment, demo policies should be replaced with authenticated reads scoped by an `org_id` / tenant column.

## Roadmap

- [ ] Realtime dashboard (React + Supabase Realtime)
- [ ] Schedule `netwatch_detect_offline()` with `pg_cron` instead of the simulator
- [ ] Per-device alert rules and configurable thresholds
- [ ] Notification fan-out (email / Slack) via an Edge Function
- [ ] Anomaly detection beyond static thresholds (rolling z-score)
- [ ] Retention policy / rollups for long-term metric storage

## License

MIT — see [`LICENSE`](./LICENSE).
