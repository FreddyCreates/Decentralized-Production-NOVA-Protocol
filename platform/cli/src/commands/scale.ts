///
/// NOVA Cloud CLI — Scale Command
///

import chalk from 'chalk';
import ora from 'ora';
import { api, getAppName } from '../lib/api.js';

export async function scaleCommand(count: string, options: { region?: string }) {
  const appName = getAppName();
  if (!appName) {
    console.error(chalk.red('✗ No app found. Create nova.toml or run: nova-cloud apps create <name>'));
    process.exit(1);
  }

  const n = parseInt(count, 10);
  if (isNaN(n) || n < 0) {
    console.error(chalk.red('✗ Count must be a positive number'));
    process.exit(1);
  }

  const spinner = ora(`Scaling ${chalk.bold(appName)} to ${n} machines...`).start();

  const result = await api(`/apps/${appName}/scale`, {
    method: 'POST',
    body: JSON.stringify({ count: n, region: options.region }),
  });

  if (!result.ok) {
    spinner.fail(result.error);
    process.exit(1);
  }

  spinner.succeed(chalk.green(`Scaled ${chalk.bold(appName)} to ${chalk.bold(String(n))} machines in ${result.data.region}`));

  if (result.data.machines && result.data.machines.length > 0) {
    console.log('');
    console.log(chalk.dim('  ' + 'ID'.padEnd(22) + 'REGION'.padEnd(15) + 'STATUS'.padEnd(12) + 'IP'));
    for (const m of result.data.machines) {
      console.log(`  ${m.id.padEnd(22)}${m.region.padEnd(15)}${m.status.padEnd(12)}${m.private_ip}`);
    }
  }
}
