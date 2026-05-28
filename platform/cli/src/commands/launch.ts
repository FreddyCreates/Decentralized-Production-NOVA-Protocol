///
/// NOVA Cloud CLI — Launch Command (Interactive)
///
/// Like `fly launch` — sets up everything for a new app.
///

import chalk from 'chalk';
import inquirer from 'inquirer';
import ora from 'ora';
import { writeFileSync } from 'fs';
import { resolve } from 'path';
import { api } from '../lib/api.js';
import { getConfig } from '../lib/config.js';

export async function launchCommand() {
  console.log(chalk.bold(`
╔══════════════════════════════════════════════════╗
║         NOVA Cloud — Launch New App              ║
╚══════════════════════════════════════════════════╝
`));

  const answers = await inquirer.prompt([
    {
      type: 'input',
      name: 'name',
      message: 'App name:',
      validate: (input: string) => /^[a-z][a-z0-9-]{2,28}[a-z0-9]$/.test(input) || 'Lowercase, 4-30 chars, alphanumeric + hyphens',
    },
    {
      type: 'list',
      name: 'region',
      message: 'Primary region:',
      choices: [
        { name: 'Sovereign Primary (sov-1)', value: 'sov-1' },
        { name: 'US East Edge (edge-us-east)', value: 'edge-us-east' },
        { name: 'US West Edge (edge-us-west)', value: 'edge-us-west' },
        { name: 'EU West Edge (edge-eu-west)', value: 'edge-eu-west' },
        { name: 'Asia Pacific Edge (edge-ap-east)', value: 'edge-ap-east' },
      ],
    },
    {
      type: 'list',
      name: 'size',
      message: 'Machine size:',
      choices: [
        { name: 'shared-cpu-1x (1 CPU, 256MB)', value: 'shared-cpu-1x' },
        { name: 'shared-cpu-2x (2 CPU, 512MB)', value: 'shared-cpu-2x' },
        { name: 'performance-1x (1 CPU, 2GB)', value: 'performance-1x' },
        { name: 'performance-2x (2 CPU, 4GB)', value: 'performance-2x' },
        { name: 'performance-4x (4 CPU, 8GB)', value: 'performance-4x' },
      ],
    },
    {
      type: 'number',
      name: 'count',
      message: 'Initial machine count:',
      default: 1,
    },
    {
      type: 'confirm',
      name: 'createToml',
      message: 'Create nova.toml in current directory?',
      default: true,
    },
  ]);

  const spinner = ora('Creating app...').start();

  const result = await api('/apps', {
    method: 'POST',
    body: JSON.stringify({ app_name: answers.name, region: answers.region }),
  });

  if (!result.ok) {
    spinner.fail(result.error);
    process.exit(1);
  }

  spinner.succeed(`App ${chalk.bold(answers.name)} created`);

  // Save current app
  const config = getConfig();
  config.set('current_app', answers.name);

  // Create nova.toml
  if (answers.createToml) {
    const toml = `# NOVA Cloud App Configuration
# https://docs.novacloud.run/reference/configuration

app = "${answers.name}"
primary_region = "${answers.region}"
kill_signal = "SIGINT"
kill_timeout = 5

[build]
  # Uncomment to use a Dockerfile
  # dockerfile = "Dockerfile"
  # Or specify a pre-built image:
  # image = "registry.novacloud.run/${answers.name}:latest"

[deploy]
  strategy = "rolling"

[env]
  NODE_ENV = "production"

[[services]]
  internal_port = 8080
  protocol = "tcp"
  auto_stop = true
  auto_start = true
  min_machines_running = 1

  [[services.ports]]
    port = 80
    handlers = ["http"]
    force_https = true

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]

  [services.concurrency]
    type = "requests"
    hard_limit = 250
    soft_limit = 200

  [[services.http_checks]]
    interval = 10000
    timeout = 2000
    grace_period = 5000
    method = "GET"
    path = "/health"

[scaling]
  min_machines = 1
  max_machines = 10
  auto_scale = true
  concurrency_target = 200

# [[mounts]]
#   source = "data"
#   destination = "/data"
#   size_gb = 1
`;

    writeFileSync(resolve(process.cwd(), 'nova.toml'), toml);
    console.log(chalk.green('✓ Created nova.toml'));
  }

  console.log(`
${chalk.bold('Your app is ready!')}

  ${chalk.dim('Deploy:')}    nova-cloud deploy --image <your-image>
  ${chalk.dim('Status:')}    nova-cloud status
  ${chalk.dim('Logs:')}      nova-cloud logs
  ${chalk.dim('Scale:')}     nova-cloud scale count ${answers.count}
  ${chalk.dim('Secrets:')}   nova-cloud secrets set KEY=VALUE
  ${chalk.dim('Dashboard:')} ${chalk.cyan(`https://dashboard.novacloud.run/apps/${answers.name}`)}
`);
}
