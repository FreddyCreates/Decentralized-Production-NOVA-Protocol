#!/usr/bin/env node
///
/// ITB Runner — Integration Test Bed Entry Point
///
/// Runs the full NOVA Protocol integration test bed on local infrastructure.
/// Validates multi-runtime and multi-substrate execution independently.
///
/// Usage:
///   node itb/run.mjs
///   npm run itb
///
/// Casa de Medina — Architectos de Architectura Inteligente
///

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { runHarness } from './harness.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dir = dirname(__filename);

// Load ITB configuration
const configPath = join(__dir, 'config.json');
const config = JSON.parse(readFileSync(configPath, 'utf-8'));

console.log('');
console.log('════════════════════════════════════════════════════════════════');
console.log('  NOVA PROTOCOL — INTEGRATION TEST BED (ITB)');
console.log('  Self-Hosted • Multi-Runtime • Multi-Substrate');
console.log('════════════════════════════════════════════════════════════════');
console.log('');
console.log(`  Mode:        Self-Hosted (own infrastructure)`);
console.log(`  Substrates:  ${config.substrates.join(', ')}`);
console.log(`  Heartbeat:   ${config.heartbeatMs}ms × ${config.heartbeatCycles} cycles`);
console.log(`  Organisms:   ${config.organisms.totalExpected} expected`);
console.log(`  Protocols:   ${config.protocols.totalExpected} expected`);
console.log(`  Timeout:     ${config.timeoutMs}ms`);
console.log('');

// Set up timeout
const timeout = setTimeout(() => {
  console.error(`\n  ⚠️  ITB TIMEOUT after ${config.timeoutMs}ms\n`);
  process.exit(2);
}, config.timeoutMs);

// Run the full harness
const { total, passed, failed } = await runHarness(config);

clearTimeout(timeout);

// Exit with appropriate code
process.exit(failed > 0 ? 1 : 0);
