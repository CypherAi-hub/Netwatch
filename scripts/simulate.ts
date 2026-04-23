import {
  createServiceClient,
  type Device,
  type MetricInsert,
} from '../src/lib/supabase.js';

const TICK_MS = Number(process.env.SIMULATE_INTERVAL_MS ?? 5000);
const ANOMALY_RATE = 0.15; // ~15% of ticks produce at least one anomalous sample

function rand(min: number, max: number) {
  return Math.random() * (max - min) + min;
}

function round2(n: number) {
  return Math.round(n * 100) / 100;
}

function sampleFor(device: Device, injectAnomaly: boolean): MetricInsert {
  // Baseline normal telemetry, with gentle per-device variance.
  let cpu = rand(10, 55);
  let mem = rand(30, 70);
  let latency = rand(1, 25);
  let loss = rand(0, 0.5);
  const bandwidth = rand(50_000, 500_000); // arbitrary units

  if (injectAnomaly) {
    const kind = Math.floor(rand(0, 4));
    if (kind === 0) cpu = rand(92, 99.5);
    else if (kind === 1) mem = rand(92, 99.5);
    else if (kind === 2) latency = rand(300, 900);
    else loss = rand(10, 40);
  }

  return {
    device_id: device.id,
    cpu_usage: round2(cpu),
    memory_usage: round2(mem),
    latency_ms: round2(latency),
    packet_loss: round2(loss),
    bandwidth_usage: round2(bandwidth),
  };
}

async function tick(supabase: ReturnType<typeof createServiceClient>) {
  const { data: devices, error } = await supabase
    .from('devices')
    .select('*')
    .returns<Device[]>();

  if (error) throw new Error(`fetch devices: ${error.message}`);
  if (!devices || devices.length === 0) {
    console.warn('No devices found. Run `npm run seed` first.');
    return;
  }

  const anomalyThisTick = Math.random() < ANOMALY_RATE;
  const samples = devices.map((d, i) =>
    sampleFor(d, anomalyThisTick && i === Math.floor(rand(0, devices.length))),
  );

  const now = new Date().toISOString();

  const [metricsRes, devicesRes] = await Promise.all([
    supabase.from('metrics').insert(samples),
    supabase
      .from('devices')
      .update({ last_seen: now, status: 'online' })
      .in(
        'id',
        devices.map((d) => d.id),
      ),
  ]);

  if (metricsRes.error) throw new Error(`insert metrics: ${metricsRes.error.message}`);
  if (devicesRes.error) throw new Error(`update last_seen: ${devicesRes.error.message}`);

  // Catch any devices that stopped reporting.
  const offlineRes = await supabase.rpc('netwatch_detect_offline');
  if (offlineRes.error) {
    console.warn('detect_offline failed:', offlineRes.error.message);
  }

  console.log(
    `[${now}] inserted ${samples.length} samples` +
      (anomalyThisTick ? ' (anomaly injected)' : '') +
      (offlineRes.data ? ` | marked ${offlineRes.data} offline` : ''),
  );
}

async function main() {
  const supabase = createServiceClient();
  console.log(`Netwatch simulator running. Tick = ${TICK_MS}ms. Ctrl+C to stop.`);

  // Run forever until interrupted.
  // eslint-disable-next-line no-constant-condition
  while (true) {
    try {
      await tick(supabase);
    } catch (err) {
      console.error('tick failed:', err);
    }
    await new Promise((r) => setTimeout(r, TICK_MS));
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
