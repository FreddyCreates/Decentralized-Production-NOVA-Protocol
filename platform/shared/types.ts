///
/// NOVA Cloud Platform — Shared Types
///
/// These types are used across the API, CLI, and Scheduler.
///

// ─── App Configuration (nova.toml parsed) ────────────────────────────────────

export interface NovaAppConfig {
  app: string;
  org?: string;
  primary_region: string;
  kill_signal?: string;
  kill_timeout?: number;

  build?: {
    image?: string;
    dockerfile?: string;
    builder?: string;
    buildpacks?: string[];
  };

  deploy?: {
    strategy?: 'rolling' | 'canary' | 'bluegreen' | 'immediate';
    max_unavailable?: number;
  };

  env?: Record<string, string>;

  services?: NovaServiceConfig[];

  scaling?: {
    min_machines?: number;
    max_machines?: number;
    auto_scale?: boolean;
    concurrency_target?: number;
  };

  mounts?: {
    source: string;
    destination: string;
    size_gb?: number;
  }[];
}

export interface NovaServiceConfig {
  internal_port: number;
  protocol: 'tcp' | 'udp';
  force_https?: boolean;
  auto_stop?: boolean;
  auto_start?: boolean;
  min_machines_running?: number;

  ports?: {
    port: number;
    handlers?: ('http' | 'tls' | 'proxy_proto')[];
    force_https?: boolean;
  }[];

  concurrency?: {
    type: 'connections' | 'requests';
    hard_limit: number;
    soft_limit: number;
  };

  http_checks?: {
    interval: number;
    timeout: number;
    grace_period: number;
    method: string;
    path: string;
  }[];
}

// ─── Core Platform Entities ──────────────────────────────────────────────────

export type AppStatus = 'pending' | 'deploying' | 'running' | 'stopped' | 'failed' | 'suspended';
export type MachineStatus = 'created' | 'starting' | 'running' | 'stopping' | 'stopped' | 'destroying' | 'destroyed';
export type DeployStatus = 'pending' | 'building' | 'pushing' | 'placing' | 'running' | 'complete' | 'failed' | 'rolled_back';

export interface App {
  id: string;
  name: string;
  org_id: string;
  status: AppStatus;
  hostname: string;
  regions: string[];
  created_at: string;
  updated_at: string;
  current_release_id?: string;
  config?: NovaAppConfig;
}

export interface Machine {
  id: string;
  app_id: string;
  name: string;
  status: MachineStatus;
  region: string;
  instance_id: string;
  private_ip: string;
  image: string;
  cpus: number;
  memory_mb: number;
  created_at: string;
  updated_at: string;
  events: MachineEvent[];
  checks?: HealthCheck[];
}

export interface MachineEvent {
  type: string;
  status: string;
  timestamp: string;
  source: string;
}

export interface HealthCheck {
  name: string;
  status: 'passing' | 'warning' | 'critical';
  output?: string;
  last_check: string;
}

export interface Release {
  id: string;
  app_id: string;
  version: number;
  image: string;
  status: DeployStatus;
  strategy: string;
  created_at: string;
  deployed_by: string;
  reason?: string;
  definition: ReleaseDefinition;
}

export interface ReleaseDefinition {
  processes: Record<string, ProcessConfig>;
  env: Record<string, string>;
  services: NovaServiceConfig[];
}

export interface ProcessConfig {
  cmd: string[];
  cpus: number;
  memory_mb: number;
  count: number;
}

export interface Secret {
  name: string;
  digest: string;
  created_at: string;
  version: number;
}

export interface LogEntry {
  timestamp: string;
  app_id: string;
  machine_id: string;
  region: string;
  level: 'info' | 'warn' | 'error' | 'debug';
  message: string;
  instance: string;
}

export interface Region {
  code: string;
  name: string;
  latitude: number;
  longitude: number;
  gateway_url: string;
  available: boolean;
}

export interface Organization {
  id: string;
  name: string;
  slug: string;
  type: 'personal' | 'team' | 'enterprise';
  created_at: string;
}

// ─── API Request/Response ────────────────────────────────────────────────────

export interface CreateAppRequest {
  app_name: string;
  org_slug?: string;
  region?: string;
}

export interface DeployRequest {
  app_id: string;
  image: string;
  strategy?: string;
  definition: ReleaseDefinition;
}

export interface ScaleRequest {
  app_id: string;
  region?: string;
  count: number;
  cpus?: number;
  memory_mb?: number;
}

export interface SetSecretsRequest {
  app_id: string;
  secrets: Record<string, string>;
}

export interface ApiResponse<T> {
  ok: boolean;
  data?: T;
  error?: string;
  request_id: string;
}

// ─── Platform Constants ──────────────────────────────────────────────────────

export const PHI = 1.618033988749895;
export const GOLDEN_ANGLE = 137.507764;

export const DEFAULT_REGIONS: Region[] = [
  { code: 'sov-1', name: 'Sovereign Primary', latitude: 0, longitude: 0, gateway_url: 'https://sov-1.novacloud.run', available: true },
  { code: 'edge-us-east', name: 'US East Edge', latitude: 39.0, longitude: -77.5, gateway_url: 'https://edge-us-east.novacloud.run', available: true },
  { code: 'edge-us-west', name: 'US West Edge', latitude: 37.8, longitude: -122.4, gateway_url: 'https://edge-us-west.novacloud.run', available: true },
  { code: 'edge-eu-west', name: 'EU West Edge', latitude: 48.9, longitude: 2.4, gateway_url: 'https://edge-eu-west.novacloud.run', available: true },
  { code: 'edge-ap-east', name: 'Asia Pacific Edge', latitude: 35.7, longitude: 139.7, gateway_url: 'https://edge-ap-east.novacloud.run', available: true },
];

export const VM_PRESETS = {
  'shared-cpu-1x': { cpus: 1, memory_mb: 256 },
  'shared-cpu-2x': { cpus: 2, memory_mb: 512 },
  'shared-cpu-4x': { cpus: 4, memory_mb: 1024 },
  'performance-1x': { cpus: 1, memory_mb: 2048 },
  'performance-2x': { cpus: 2, memory_mb: 4096 },
  'performance-4x': { cpus: 4, memory_mb: 8192 },
  'performance-8x': { cpus: 8, memory_mb: 16384 },
} as const;
