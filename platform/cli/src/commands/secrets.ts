///
/// NOVA Cloud CLI — Secrets Commands
///

import chalk from 'chalk';
import { api, getAppName } from '../lib/api.js';

export const secretsCommands = {
  async list() {
    const appName = getAppName();
    if (!appName) {
      console.error(chalk.red('✗ No app found'));
      process.exit(1);
    }

    const result = await api(`/secrets/${appName}`);
    if (!result.ok) {
      console.error(chalk.red(`✗ ${result.error}`));
      process.exit(1);
    }

    if (result.data.length === 0) {
      console.log(chalk.yellow('No secrets set. Add with: nova-cloud secrets set KEY=VALUE'));
      return;
    }

    console.log(chalk.bold(`\nSecrets for ${appName}:\n`));
    console.log('  ' + chalk.dim('NAME'.padEnd(30) + 'DIGEST'.padEnd(20) + 'VERSION'.padEnd(10) + 'SET AT'));
    console.log('  ' + chalk.dim('─'.repeat(75)));
    for (const s of result.data) {
      console.log(`  ${s.name.padEnd(30)}${s.digest.padEnd(20)}v${String(s.version).padEnd(9)}${s.created_at}`);
    }
  },

  async set(pairs: string[]) {
    const appName = getAppName();
    if (!appName) {
      console.error(chalk.red('✗ No app found'));
      process.exit(1);
    }

    const secrets: Record<string, string> = {};
    for (const pair of pairs) {
      const eqIdx = pair.indexOf('=');
      if (eqIdx === -1) {
        console.error(chalk.red(`✗ Invalid format: ${pair}. Use KEY=VALUE`));
        process.exit(1);
      }
      secrets[pair.slice(0, eqIdx)] = pair.slice(eqIdx + 1);
    }

    const result = await api(`/secrets/${appName}`, {
      method: 'POST',
      body: JSON.stringify({ secrets }),
    });

    if (!result.ok) {
      console.error(chalk.red(`✗ ${result.error}`));
      process.exit(1);
    }

    for (const s of result.data.set) {
      console.log(chalk.green(`✓ ${s.name} ${s.action}`));
    }

    if (result.data.deploy_needed) {
      console.log(chalk.yellow('\n  Secrets changed. Redeploy to apply: nova-cloud deploy'));
    }
  },

  async unset(names: string[]) {
    const appName = getAppName();
    if (!appName) {
      console.error(chalk.red('✗ No app found'));
      process.exit(1);
    }

    for (const name of names) {
      const result = await api(`/secrets/${appName}/${name}`, { method: 'DELETE' });
      if (result.ok) {
        console.log(chalk.green(`✓ ${name} removed`));
      } else {
        console.error(chalk.red(`✗ ${name}: ${result.error}`));
      }
    }
  },
};
