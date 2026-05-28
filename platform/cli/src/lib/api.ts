///
/// NOVA Cloud CLI — API Client
///

import { readFileSync } from 'fs';
import { resolve } from 'path';
import { getConfig } from './config.js';

const DEFAULT_API = 'http://localhost:4000';

export function getApiUrl(): string {
  const config = getConfig();
  return config.get('api_url') || process.env.NOVA_API_URL || DEFAULT_API;
}

export function getToken(): string | null {
  const config = getConfig();
  return config.get('token') || process.env.NOVA_TOKEN || null;
}

export async function api<T = any>(path: string, options: RequestInit = {}): Promise<{ ok: boolean; data?: T; error?: string }> {
  const token = getToken();
  const url = `${getApiUrl()}/v1${path}`;

  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...(options.headers as Record<string, string> || {}),
  };

  if (token) {
    headers['Authorization'] = `******;
  }

  const response = await fetch(url, {
    ...options,
    headers,
  });

  const json = await response.json() as any;
  return json;
}

export function getAppName(): string | null {
  // Try nova.toml in current directory
  try {
    const tomlPath = resolve(process.cwd(), 'nova.toml');
    const content = readFileSync(tomlPath, 'utf-8');
    const match = content.match(/^app\s*=\s*"([^"]+)"/m);
    if (match) return match[1];
  } catch {}

  // Try config
  const config = getConfig();
  return config.get('current_app') || null;
}
