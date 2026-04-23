export type DemoDevice = {
  hostname: string;
  ip_address: string;
  device_type: string;
  location: string;
};

export const DEMO_DEVICES: DemoDevice[] = [
  {
    hostname: 'core-router-01',
    ip_address: '10.0.1.1',
    device_type: 'router',
    location: 'HQ / DC-East',
  },
  {
    hostname: 'edge-fw-01',
    ip_address: '10.0.1.2',
    device_type: 'firewall',
    location: 'HQ / DC-East',
  },
  {
    hostname: 'tor-switch-a1',
    ip_address: '10.0.2.10',
    device_type: 'switch',
    location: 'HQ / DC-East',
  },
  {
    hostname: 'web-app-01',
    ip_address: '10.0.3.21',
    device_type: 'server',
    location: 'HQ / DC-East',
  },
  {
    hostname: 'db-primary-01',
    ip_address: '10.0.3.40',
    device_type: 'server',
    location: 'HQ / DC-East',
  },
  {
    hostname: 'branch-router-sea',
    ip_address: '10.10.1.1',
    device_type: 'router',
    location: 'Branch / Seattle',
  },
  {
    hostname: 'branch-ap-sea-01',
    ip_address: '10.10.2.5',
    device_type: 'access_point',
    location: 'Branch / Seattle',
  },
];
