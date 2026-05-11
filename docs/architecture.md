# Architecture

Netwatch is intentionally small. All business logic that can live in the database does — the only moving part outside Postgres is a TypeScript simulator.

## Components

### Postgres (Supabase)
- Three tables: `devices`, `metrics`, `alerts`.
- One trigger (`metrics_evaluate_alerts`) and three functions (`netwatch_upsert_alert`, `netwatch_evaluate_metric`, `netwatch_detect_offline`).
- Row Level Security on every table. Writes are service-role only; reads are public for demo convenience.

### Simulator (`scripts/simulate.ts`)
- Connects as service role.
- Every `SIMULATE_INTERVAL_MS` (default 5000 ms):
  1. Loads all devices.
  2. Generates a synthetic metric sample per device.
  3. With probability `ANOMALY_RATE` (default 0.15), one random sample is pushed past a threshold.
  4. Inserts samples (which fires the alerting trigger).
  5. Calls `rpc('netwatch_detect_offline')` to catch devices that have gone silent.

### Seed (`scripts/seed.ts`)
- Upserts 7 realistic demo devices by `ip_address`. Safe to run repeatedly.

## Request flow

```
simulator.tick()
  ├─ select * from devices
  ├─ insert into metrics (...)           ─┐
  │     └─ trigger metrics_evaluate_alerts│
  │           ├─ update devices.last_seen, status
  │           ├─ resolve device_offline (if open)
  │           └─ for each threshold:
  │                netwatch_upsert_alert(...)
  │                  ├─ insert into alerts (if breached and none open)
  │                  └─ update alerts set resolved=true (if cleared)
  ├─ update devices.last_seen in bulk  (belt-and-suspenders)
  └─ rpc netwatch_detect_offline()
         ├─ mark stale devices offline
         └─ insert device_offline alerts
```

## Why DB-first?

- One source of truth for alerting logic.
- No extra services to deploy, monitor, or pay for.
- Trivial to unit-test with plain SQL.
- Swapping the simulator for real telemetry later (SNMP poller, agent, webhook) does not change the alerting surface.

## Known tradeoffs

- **Static thresholds.** Not adaptive. Fine for a demo, less good in practice.
- **Single-tenant.** No `org_id` column yet; demo RLS is intentionally permissive.
- **No retention.** `metrics` grows forever. Add a scheduled delete or a rollup table before running this at scale.
- **Offline detection leans on the simulator.** Moving to `pg_cron` is a one-line migration when you're ready.
