///
/// NOVA Cloud — Proxy Configuration Generator
///
/// Generates Traefik dynamic configuration for routing traffic
/// to deployed apps based on hostname (*.novacloud.run)
///

import { db } from '../api/db/index.js';

export interface TraefikRoute {
  rule: string;
  service: string;
  entryPoints: string[];
}

export function generateRoutes(): TraefikRoute[] {
  const apps = db.conn.prepare("SELECT * FROM apps WHERE status = 'running'").all() as any[];
  const routes: TraefikRoute[] = [];

  for (const app of apps) {
    const machines = db.conn.prepare(
      "SELECT * FROM machines WHERE app_id = ? AND status = 'running'"
    ).all(app.id) as any[];

    if (machines.length > 0) {
      routes.push({
        rule: `Host(\`${app.name}.novacloud.run\`)`,
        service: `svc-${app.name}`,
        entryPoints: ['web', 'websecure'],
      });
    }
  }

  return routes;
}
