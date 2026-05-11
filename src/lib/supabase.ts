import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import 'dotenv/config';

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

export function createServiceClient(): SupabaseClient {
  return createClient(
    requireEnv('SUPABASE_URL'),
    requireEnv('SUPABASE_SERVICE_ROLE_KEY'),
    {
      auth: { persistSession: false, autoRefreshToken: false },
    },
  );
}

export type Device = {
  id: string;
  hostname: string;
  ip_address: string;
  device_type: string;
  location: string | null;
  status: 'online' | 'offline' | 'degraded' | 'unknown';
  last_seen: string | null;
  created_at: string;
};

export type MetricInsert = {
  device_id: string;
  cpu_usage?: number;
  memory_usage?: number;
  latency_ms?: number;
  packet_loss?: number;
  bandwidth_usage?: number;
};
