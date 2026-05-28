///
/// NOVA Cloud CLI — Init Command
///
/// Creates a nova.toml in the current directory.
///

import chalk from 'chalk';
import inquirer from 'inquirer';
import { writeFileSync, existsSync } from 'fs';
import { resolve } from 'path';

export async function initCommand() {
  const tomlPath = resolve(process.cwd(), 'nova.toml');

  if (existsSync(tomlPath)) {
    console.log(chalk.yellow('nova.toml already exists in this directory'));
    const { overwrite } = await inquirer.prompt([{
      type: 'confirm',
      name: 'overwrite',
      message: 'Overwrite?',
      default: false,
    }]);
    if (!overwrite) return;
  }

  const { name } = await inquirer.prompt([{
    type: 'input',
    name: 'name',
    message: 'App name:',
    validate: (input: string) => /^[a-z][a-z0-9-]{2,28}[a-z0-9]$/.test(input) || 'Lowercase, 4-30 chars',
  }]);

  const toml = `# NOVA Cloud App Configuration
app = "${name}"
primary_region = "sov-1"
kill_signal = "SIGINT"
kill_timeout = 5

[build]
  dockerfile = "Dockerfile"

[deploy]
  strategy = "rolling"

[env]
  NODE_ENV = "production"

[[services]]
  internal_port = 8080
  protocol = "tcp"
  auto_stop = true
  auto_start = true

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

[scaling]
  min_machines = 1
  max_machines = 10
  auto_scale = true
`;

  writeFileSync(tomlPath, toml);
  console.log(chalk.green(`✓ Created nova.toml for ${chalk.bold(name)}`));
}
