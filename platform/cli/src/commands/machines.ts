///
/// NOVA Cloud CLI — Machines Commands
///

import chalk from 'chalk';
import { api, getAppName } from '../lib/api.js';

export const machinesCommands = {
  async list() {
    const appName = getAppName();
    if (!appName) {
      console.error(chalk.red('✗ No app found'));
      process.exit(1);
    }

    const result = await api(`/machines?app=${appName}`);
    if (!result.ok) {
      console.error(chalk.red(`✗ ${result.error}`));
      process.exit(1);
    }

    if (result.data.length === 0) {
      console.log(chalk.yellow('No machines. Deploy first: nova-cloud deploy'));
      return;
    }

    console.log(chalk.bold(`\nMachines for ${appName}:\n`));
    console.log('  ' + chalk.dim('ID'.padEnd(22) + 'NAME'.padEnd(28) + 'REGION'.padEnd(15) + 'STATUS'.padEnd(12) + 'IP'.padEnd(20) + 'IMAGE'));
    console.log('  ' + chalk.dim('─'.repeat(110)));
    for (const m of result.data) {
      const sColor = m.status === 'running' ? chalk.green : m.status === 'starting' ? chalk.yellow : chalk.red;
      console.log(
        `  ${m.id.padEnd(22)}${m.name.padEnd(28)}${m.region.padEnd(15)}${sColor(m.status.padEnd(12))}${(m.private_ip || '').padEnd(20)}${m.image || ''}`
      );
    }
  },

  async stop(id: string) {
    const result = await api(`/machines/${id}/stop`, { method: 'POST' });
    if (!result.ok) {
      console.error(chalk.red(`✗ ${result.error}`));
      process.exit(1);
    }
    console.log(chalk.green(`✓ Machine ${id} stopped`));
  },

  async start(id: string) {
    const result = await api(`/machines/${id}/start`, { method: 'POST' });
    if (!result.ok) {
      console.error(chalk.red(`✗ ${result.error}`));
      process.exit(1);
    }
    console.log(chalk.green(`✓ Machine ${id} started`));
  },

  async destroy(id: string) {
    const result = await api(`/machines/${id}`, { method: 'DELETE' });
    if (!result.ok) {
      console.error(chalk.red(`✗ ${result.error}`));
      process.exit(1);
    }
    console.log(chalk.green(`✓ Machine ${id} destroyed`));
  },
};
