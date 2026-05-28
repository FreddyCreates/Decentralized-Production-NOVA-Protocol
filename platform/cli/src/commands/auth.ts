///
/// NOVA Cloud CLI — Auth Commands
///

import chalk from 'chalk';
import inquirer from 'inquirer';
import { api, getToken } from '../lib/api.js';
import { getConfig } from '../lib/config.js';

export const authCommands = {
  async signup() {
    const answers = await inquirer.prompt([
      { type: 'input', name: 'email', message: 'Email:' },
      { type: 'password', name: 'password', message: 'Password:', mask: '*' },
      { type: 'input', name: 'name', message: 'Name (optional):' },
    ]);

    const result = await api('/auth/signup', {
      method: 'POST',
      body: JSON.stringify(answers),
    });

    if (!result.ok) {
      console.error(chalk.red(`✗ ${result.error}`));
      process.exit(1);
    }

    const config = getConfig();
    config.set('token', result.data.api_token);
    config.set('user_email', answers.email);
    config.set('user_id', result.data.user_id);
    config.set('org_id', result.data.org_id);

    console.log(chalk.green(`✓ Account created! Logged in as ${chalk.bold(answers.email)}`));
    console.log(chalk.dim(`  API Token: ${result.data.api_token}`));
    console.log(chalk.dim(`  Save this token — you'll need it for CI/CD`));
  },

  async login() {
    const answers = await inquirer.prompt([
      { type: 'input', name: 'email', message: 'Email:' },
      { type: 'password', name: 'password', message: 'Password:', mask: '*' },
    ]);

    const result = await api('/auth/login', {
      method: 'POST',
      body: JSON.stringify(answers),
    });

    if (!result.ok) {
      console.error(chalk.red(`✗ ${result.error}`));
      process.exit(1);
    }

    const config = getConfig();
    config.set('token', result.data.api_token);
    config.set('user_email', answers.email);
    config.set('user_id', result.data.user_id);
    config.set('org_id', result.data.org_id);

    console.log(chalk.green(`✓ Logged in as ${chalk.bold(answers.email)}`));
  },

  async logout() {
    const config = getConfig();
    config.clear();
    console.log(chalk.green('✓ Logged out'));
  },

  async whoami() {
    const token = getToken();
    if (!token) {
      console.log(chalk.yellow('Not logged in. Run: nova-cloud auth login'));
      return;
    }

    const result = await api('/auth/tokens');
    if (!result.ok) {
      console.log(chalk.yellow('Not logged in or token expired. Run: nova-cloud auth login'));
      return;
    }

    console.log(chalk.bold('Current User:'));
    console.log(`  Email: ${result.data.email}`);
    console.log(`  ID:    ${result.data.id}`);
    console.log(`  Org:   ${result.data.org_id}`);
  },

  async token() {
    const config = getConfig();
    const token = config.get('token');
    if (!token) {
      console.log(chalk.yellow('Not logged in'));
      return;
    }
    console.log(token);
  },
};
