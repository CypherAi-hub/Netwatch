-- Netwatch :: 0004_alerts
-- Threshold-based alert generation.
--
--   Metric alerts: AFTER INSERT trigger on `metrics` opens/closes alerts
--                  for high CPU, high memory, latency spike, high packet loss.
--   Device state: every fresh metric also bumps last_seen, flips status back
--                 to 'online', and resolves any open device_offline alert.
--   Offline alerts: `netwatch_detect_offline()` is called periodically
--                  (by the simulator today, pg_cron later) to catch devices
--                  that have gone silent.
--
-- Functions are SECURITY DEFINER with an explicit search_path so they pass
-- Supabase security lints and behave predictably regardless of caller role.

-- Opens an alert if breached and none is currently open; otherwise auto-resolves.
create or replace function public.netwatch_upsert_alert(
    p_device_id  uuid,
    p_alert_type text,
    p_severity   text,
    p_breached   boolean,
    p_message    text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if p_breached then
        insert into public.alerts (device_id, alert_type, severity, message)
        select p_device_id, p_alert_type, p_severity, p_message
        where not exists (
            select 1
              from public.alerts
             where device_id  = p_device_id
               and alert_type = p_alert_type
               and resolved   = false
        );
    else
        update public.alerts
           set resolved    = true,
               resolved_at = now()
         where device_id  = p_device_id
           and alert_type = p_alert_type
           and resolved   = false;
    end if;
end;
$$;

-- Trigger function: evaluates each metric row against thresholds AND restores
-- device state (last_seen / status / device_offline alert) on telemetry arrival.
create or replace function public.netwatch_evaluate_metric()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    -- Device state: fresh telemetry means the device is alive.
    update public.devices
       set last_seen = coalesce(new.recorded_at, now()),
           status    = 'online'
     where id = new.device_id;

    -- Clear any open device_offline alert now that we're receiving data again.
    perform public.netwatch_upsert_alert(
        new.device_id, 'device_offline', 'critical',
        false, 'Telemetry resumed'
    );

    -- Threshold checks.
    perform public.netwatch_upsert_alert(
        new.device_id, 'high_cpu', 'high',
        new.cpu_usage is not null and new.cpu_usage >= 90,
        format('CPU usage at %s%% (threshold 90%%)', new.cpu_usage)
    );

    perform public.netwatch_upsert_alert(
        new.device_id, 'high_memory', 'high',
        new.memory_usage is not null and new.memory_usage >= 90,
        format('Memory usage at %s%% (threshold 90%%)', new.memory_usage)
    );

    perform public.netwatch_upsert_alert(
        new.device_id, 'latency_spike', 'medium',
        new.latency_ms is not null and new.latency_ms >= 250,
        format('Latency at %sms (threshold 250ms)', new.latency_ms)
    );

    perform public.netwatch_upsert_alert(
        new.device_id, 'high_packet_loss', 'medium',
        new.packet_loss is not null and new.packet_loss >= 5,
        format('Packet loss at %s%% (threshold 5%%)', new.packet_loss)
    );

    return new;
end;
$$;

drop trigger if exists metrics_evaluate_alerts on public.metrics;
create trigger metrics_evaluate_alerts
    after insert on public.metrics
    for each row
    execute function public.netwatch_evaluate_metric();

-- Offline detection: marks stale devices offline, opens device_offline alerts.
-- Call periodically from the simulator (or later from pg_cron).
create or replace function public.netwatch_detect_offline(
    p_threshold interval default interval '2 minutes'
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    _marked_offline integer := 0;
begin
    -- 1. Mark devices offline whose last_seen is too old.
    update public.devices
       set status = 'offline'
     where last_seen is not null
       and last_seen < now() - p_threshold
       and status <> 'offline';

    get diagnostics _marked_offline = row_count;

    -- 2. Open a device_offline alert for any offline device without one.
    insert into public.alerts (device_id, alert_type, severity, message)
    select d.id,
           'device_offline',
           'critical',
           format('Device has not reported since %s', d.last_seen)
      from public.devices d
     where d.status = 'offline'
       and not exists (
           select 1
             from public.alerts a
            where a.device_id  = d.id
              and a.alert_type = 'device_offline'
              and a.resolved   = false
       );

    return _marked_offline;
end;
$$;
