#!/usr/bin/env node
///
/// nova-cloud — The NOVA Cloud Platform CLI
///
/// Like flyctl, but sovereign. YOUR platform.
///
/// Usage:
///   nova-cloud auth signup
///   nova-cloud auth login
///   nova-cloud apps create my-app
///   nova-cloud deploy
///   nova-cloud scale count 3
///   nova-cloud secrets set DATABASE_URL=postgres://...
///   nova-cloud logs
///   nova-cloud status
///   nova-cloud machines list
///   nova-cloud regions list
///

import { Command } from 'commander';
import chalk from 'chalk';
import { authCommands } from '../src/commands/auth.js';
import { appsCommands } from '../src/commands/apps.js';
import { deployCommand } from '../src/commands/deploy.js';
import { scaleCommand } from '../src/commands/scale.js';
import { secretsCommands } from '../src/commands/secrets.js';
import { logsCommand } from '../src/commands/logs.js';
import { statusCommand } from '../src/commands/status.js';
import { machinesCommands } from '../src/commands/machines.js';
import { regionsCommand } from '../src/commands/regions.js';

const program = new Command();

program
  .name('nova-cloud')
  .description(`${chalk.bold('NOVA Cloud')} — Sovereign Edge Platform CLI\nYour infrastructure. Your rules. Deploy globally.`)
  .version('0.1.0');

// Auth
const auth = program.command('auth').description('Authentication commands');
auth.command('signup').description('Create a new account').action(authCommands.signup);
auth.command('login').description('Log in to NOVA Cloud').action(authCommands.login);
auth.command('logout').description('Log out').action(authCommands.logout);
auth.command('whoami').description('Show current user').action(authCommands.whoami);
auth.command('token').description('Show API token').action(authCommands.token);

// Apps
const apps = program.command('apps').description('Manage applications');
apps.command('create <name>').description('Create a new app').option('-r, --region <region>', 'Primary region').action(appsCommands.create);
apps.command('list').description('List all apps').action(appsCommands.list);
apps.command('info [name]').description('Show app details').action(appsCommands.info);
apps.command('destroy <name>').description('Destroy an app').option('--yes', 'Skip confirmation').action(appsCommands.destroy);

// Deploy
program.command('deploy').description('Deploy the current app').option('-i, --image <image>', 'Docker image to deploy').option('--strategy <strategy>', 'Deploy strategy (rolling/canary/bluegreen)').action(deployCommand);

// Scale
const scale = program.command('scale').description('Scale app machines');
scale.command('count <count>').description('Set machine count').option('-r, --region <region>', 'Target region').action(scaleCommand);

// Secrets
const secrets = program.command('secrets').description('Manage app secrets');
secrets.command('list').description('List all secrets').action(secretsCommands.list);
secrets.command('set <pairs...>').description('Set secrets (KEY=VALUE ...)').action(secretsCommands.set);
secrets.command('unset <names...>').description('Remove secrets').action(secretsCommands.unset);

// Logs
program.command('logs').description('View app logs').option('-f, --follow', 'Follow log output').option('-r, --region <region>', 'Filter by region').action(logsCommand);

// Status
program.command('status').description('Show app status').action(statusCommand);

// Machines
const machines = program.command('machines').description('Manage individual machines');
machines.command('list').description('List machines').action(machinesCommands.list);
machines.command('stop <id>').description('Stop a machine').action(machinesCommands.stop);
machines.command('start <id>').description('Start a machine').action(machinesCommands.start);
machines.command('destroy <id>').description('Destroy a machine').action(machinesCommands.destroy);

// Regions
program.command('regions').description('List available regions').action(regionsCommand);

// Launch (interactive setup — like `fly launch`)
program.command('launch').description('Create and configure a new app interactively').action(async () => {
  const { launchCommand } = await import('../src/commands/launch.js');
  await launchCommand();
});

// Init (create nova.toml)
program.command('init').description('Create nova.toml in current directory').action(async () => {
  const { initCommand } = await import('../src/commands/init.js');
  await initCommand();
});

program.parse();
