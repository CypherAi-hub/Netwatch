import { createServiceClient } from '../src/lib/supabase.js';
import { DEMO_DEVICES } from '../src/lib/devices.js';

async function main() {
  const supabase = createServiceClient();

  const { data, error } = await supabase
    .from('devices')
    .upsert(DEMO_DEVICES, { onConflict: 'ip_address' })
    .select('id, hostname, ip_address');

  if (error) {
    console.error('Seed failed:', error.message);
    process.exit(1);
  }

  console.log(`Seeded ${data?.length ?? 0} devices:`);
  for (const d of data ?? []) {
    console.log(`  - ${d.hostname.padEnd(22)} ${d.ip_address}`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
