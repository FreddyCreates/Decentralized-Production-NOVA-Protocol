///
/// NOVA Cloud CLI — Regions Command
///

import chalk from 'chalk';
import { api } from '../lib/api.js';

export async function regionsCommand() {
  const result = await api('/regions');
  if (!result.ok) {
    console.error(chalk.red(`✗ ${result.error}`));
    process.exit(1);
  }

  console.log(chalk.bold('\nNOVA Cloud Regions:\n'));
  console.log('  ' + chalk.dim('CODE'.padEnd(18) + 'NAME'.padEnd(25) + 'STATUS'));
  console.log('  ' + chalk.dim('─'.repeat(55)));

  for (const r of result.data) {
    const status = r.available ? chalk.green('● available') : chalk.red('○ unavailable');
    console.log(`  ${chalk.bold(r.code.padEnd(18))}${r.name.padEnd(25)}${status}`);
  }
}
