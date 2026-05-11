-- Netwatch :: 0002_metric_ranges
-- Data-quality CHECK constraints on metrics columns.
-- Percent-based metrics clamp to [0, 100]; non-negative metrics clamp to >= 0.
-- NULLs are allowed (columns are nullable and CHECK treats NULL as pass).

alter table public.metrics
    add constraint metrics_cpu_usage_range
        check (cpu_usage is null or cpu_usage between 0 and 100),
    add constraint metrics_memory_usage_range
        check (memory_usage is null or memory_usage between 0 and 100),
    add constraint metrics_packet_loss_range
        check (packet_loss is null or packet_loss between 0 and 100),
    add constraint metrics_latency_ms_nonneg
        check (latency_ms is null or latency_ms >= 0),
    add constraint metrics_bandwidth_usage_nonneg
        check (bandwidth_usage is null or bandwidth_usage >= 0);
