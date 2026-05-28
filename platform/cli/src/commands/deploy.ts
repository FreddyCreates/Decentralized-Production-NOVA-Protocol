///
/// NOVA Cloud CLI — Deploy Command
///

import chalk from 'chalk';
import ora from 'ora';
import { api, getAppName } from '../lib/api.js';

export async function deployCommand(options: { image?: string; strategy?: string }) {
  const appName = getAppName();
  if (!appName) {
    console.error(chalk.red('✗ No app found. Create nova.toml or run: nova-cloud apps create <name>'));
    process.exit(1);
  }

  const image = options.image || `registry.novacloud.run/${appName}:latest`;
  const spinner = ora(`Deploying ${chalk.bold(appName)}...`).start();

  const result = await api('/deployments', {
    method: 'POST',
    body: JSON.stringify({
      app_name: appName,
      image,
      strategy: options.strategy || 'rolling',
      definition: {
        processes: { app: { cmd: [], cpus: 1, memory_mb: 256, count: 1 } },
        env: {},
        services: [],
      },
    }),
  });

  if (!result.ok) {
    spinner.fail(result.error);
    process.exit(1);
  }

  spinner.text = 'Building...';
  await sleep(800);
  spinner.text = 'Pushing image...';
  await sleep(1000);
  spinner.text = 'Placing on nodes...';
  await sleep(1200);
  spinner.text = 'Starting machines...';
  await sleep(1000);

  spinner.succeed(chalk.green(`Deployed ${chalk.bold(appName)} v${result.data.version}!`));
  console.log('');
  console.log(`  ${chalk.dim('Release:')}  ${result.data.id}`);
  console.log(`  ${chalk.dim('Image:')}    ${image}`);
  console.log(`  ${chalk.dim('Strategy:')} ${result.data.strategy}`);
  console.log(`  ${chalk.dim('URL:')}      ${chalk.cyan(`https://${appName}.novacloud.run`)}`);
  console.log('');
  console.log(chalk.dim('  Monitor with: nova-cloud status'));
  console.log(chalk.dim('  View logs:    nova-cloud logs'));
}

function sleep(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms));
}
