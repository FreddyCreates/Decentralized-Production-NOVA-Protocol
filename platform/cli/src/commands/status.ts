///
/// NOVA Cloud CLI — Status Command
///

import chalk from 'chalk';
import { api, getAppName } from '../lib/api.js';

export async function statusCommand() {
  const appName = getAppName();
  if (!appName) {
    console.error(chalk.red('✗ No app found. Create nova.toml or specify app name'));
    process.exit(1);
  }

  const [appResult, machinesResult] = await Promise.all([
    api(`/apps/${appName}`),
    api(`/machines?app=${appName}`),
  ]);

  if (!appResult.ok) {
    console.error(chalk.red(`✗ ${appResult.error}`));
    process.exit(1);
  }

  const app = appResult.data;
  const machines = machinesResult.data || [];

  const statusIcon = app.status === 'running' ? chalk.green('●') : app.status === 'deploying' ? chalk.yellow('◐') : chalk.red('○');

  console.log(`
${chalk.bold('NOVA Cloud')} — App Status
${'─'.repeat(50)}

  ${statusIcon} ${chalk.bold(app.name)}
  
  Status:    ${app.status === 'running' ? chalk.green(app.status) : chalk.yellow(app.status)}
  Hostname:  ${chalk.cyan(app.hostname)}
  URL:       ${chalk.cyan(`https://${app.hostname}`)}
  Regions:   ${app.regions}
  Release:   ${app.current_release_id || chalk.dim('none')}
  Updated:   ${app.updated_at}

${chalk.bold('Machines')} (${machines.length})
${'─'.repeat(50)}
`);

  if (machines.length === 0) {
    console.log(chalk.yellow('  No machines running. Deploy with: nova-cloud deploy'));
  } else {
    console.log('  ' + chalk.dim('ID'.padEnd(22) + 'NAME'.padEnd(28) + 'REGION'.padEnd(15) + 'STATUS'.padEnd(12) + 'CPU  MEM'));
    for (const m of machines) {
      const sColor = m.status === 'running' ? chalk.green : m.status === 'starting' ? chalk.yellow : chalk.red;
      console.log(
        `  ${m.id.padEnd(22)}${m.name.padEnd(28)}${m.region.padEnd(15)}${sColor(m.status.padEnd(12))}${m.cpus}    ${m.memory_mb}MB`
      );
    }
  }
}
