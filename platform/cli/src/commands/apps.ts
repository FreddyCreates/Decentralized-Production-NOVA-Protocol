///
/// NOVA Cloud CLI — Apps Commands
///

import chalk from 'chalk';
import { api, getAppName } from '../lib/api.js';

export const appsCommands = {
  async create(name: string, options: { region?: string }) {
    const result = await api('/apps', {
      method: 'POST',
      body: JSON.stringify({ app_name: name, region: options.region }),
    });

    if (!result.ok) {
      console.error(chalk.red(`✗ ${result.error}`));
      process.exit(1);
    }

    console.log(chalk.green(`✓ App ${chalk.bold(name)} created!`));
    console.log(`  Hostname: ${chalk.cyan(result.data.hostname)}`);
    console.log(`  Region:   ${result.data.regions}`);
    console.log(`  Status:   ${result.data.status}`);
    console.log('');
    console.log(chalk.dim('  Deploy with: nova-cloud deploy --image <your-image>'));
  },

  async list() {
    const result = await api('/apps');

    if (!result.ok) {
      console.error(chalk.red(`✗ ${result.error}`));
      process.exit(1);
    }

    if (result.data.length === 0) {
      console.log(chalk.yellow('No apps yet. Create one with: nova-cloud apps create <name>'));
      return;
    }

    console.log(chalk.bold('Your Apps:\n'));
    console.log('  ' + chalk.dim('NAME'.padEnd(25) + 'STATUS'.padEnd(12) + 'HOSTNAME'.padEnd(35) + 'REGIONS'));
    console.log('  ' + chalk.dim('─'.repeat(85)));

    for (const app of result.data) {
      const statusColor = app.status === 'running' ? chalk.green : app.status === 'deploying' ? chalk.yellow : chalk.gray;
      console.log(
        '  ' +
        chalk.bold(app.name.padEnd(25)) +
        statusColor(app.status.padEnd(12)) +
        chalk.cyan(app.hostname.padEnd(35)) +
        app.regions
      );
    }
  },

  async info(name?: string) {
    const appName = name || getAppName();
    if (!appName) {
      console.error(chalk.red('✗ No app specified. Pass app name or create nova.toml'));
      process.exit(1);
    }

    const result = await api(`/apps/${appName}`);
    if (!result.ok) {
      console.error(chalk.red(`✗ ${result.error}`));
      process.exit(1);
    }

    const app = result.data;
    console.log(chalk.bold(`\nApp: ${app.name}\n`));
    console.log(`  Status:    ${app.status === 'running' ? chalk.green(app.status) : chalk.yellow(app.status)}`);
    console.log(`  Hostname:  ${chalk.cyan(app.hostname)}`);
    console.log(`  Regions:   ${app.regions}`);
    console.log(`  Created:   ${app.created_at}`);
    console.log(`  Updated:   ${app.updated_at}`);
    if (app.current_release_id) {
      console.log(`  Release:   ${app.current_release_id}`);
    }
  },

  async destroy(name: string, options: { yes?: boolean }) {
    if (!options.yes) {
      const inquirer = await import('inquirer');
      const { confirm } = await inquirer.default.prompt([{
        type: 'confirm',
        name: 'confirm',
        message: chalk.red(`Destroy app ${chalk.bold(name)}? This cannot be undone.`),
        default: false,
      }]);
      if (!confirm) return;
    }

    const result = await api(`/apps/${name}`, { method: 'DELETE' });
    if (!result.ok) {
      console.error(chalk.red(`✗ ${result.error}`));
      process.exit(1);
    }

    console.log(chalk.green(`✓ App ${chalk.bold(name)} destroyed`));
  },
};
