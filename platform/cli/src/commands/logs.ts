///
/// NOVA Cloud CLI — Logs Command
///

import chalk from 'chalk';
import { api, getAppName } from '../lib/api.js';

export async function logsCommand(options: { follow?: boolean; region?: string }) {
  const appName = getAppName();
  if (!appName) {
    console.error(chalk.red('✗ No app found'));
    process.exit(1);
  }

  const params = new URLSearchParams();
  if (options.region) params.set('region', options.region);
  params.set('limit', '50');

  const result = await api(`/logs/${appName}?${params.toString()}`);
  if (!result.ok) {
    console.error(chalk.red(`✗ ${result.error}`));
    process.exit(1);
  }

  for (const log of result.data) {
    const levelColor = log.level === 'error' ? chalk.red : log.level === 'warn' ? chalk.yellow : chalk.dim;
    const ts = chalk.dim(log.timestamp);
    const region = chalk.cyan(log.region || '');
    const machine = chalk.dim(log.machine_id?.slice(0, 8) || '');
    console.log(`${ts} ${region} ${machine} ${levelColor(log.level.toUpperCase().padEnd(5))} ${log.message}`);
  }

  if (options.follow) {
    console.log(chalk.dim('\n── Following logs (Ctrl+C to stop) ──'));
    // In production this would use WebSocket
    const interval = setInterval(async () => {
      const r = await api(`/logs/${appName}?limit=5`);
      if (r.ok && r.data.length > 0) {
        for (const log of r.data) {
          const levelColor = log.level === 'error' ? chalk.red : log.level === 'warn' ? chalk.yellow : chalk.dim;
          console.log(`${chalk.dim(log.timestamp)} ${chalk.cyan(log.region || '')} ${levelColor(log.level.toUpperCase().padEnd(5))} ${log.message}`);
        }
      }
    }, 2000);

    process.on('SIGINT', () => {
      clearInterval(interval);
      process.exit(0);
    });
  }
}
