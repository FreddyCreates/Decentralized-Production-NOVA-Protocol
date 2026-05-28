# ITB — Integration Test Bed

Self-hosted multi-runtime and multi-substrate integration test bed for the NOVA Protocol.

## Overview

The ITB bootstraps the entire NOVA runtime locally on your own infrastructure — no
external network or IC mainnet dependency required. It exercises all 6 substrate
execution paths (Motoko, TypeScript, Python, C++, Java, WebWorker) and validates
cross-substrate coordination, Kuramoto synchronization, and protocol binding in a
single deterministic run.

## Running

```bash
# Run the full ITB suite
npm run itb

# Or directly:
node itb/run.mjs
```

## What It Tests

1. **Self-Hosted Bootstrap** — Full system start on local infra, no external deps
2. **Multi-Runtime Execution** — All 6 substrate executors invoked and validated
3. **Substrate Registration** — Organisms correctly assigned to substrate types
4. **Protocol Binding** — All 129 protocols bound and routable
5. **Heartbeat Lifecycle** — 873ms φ-heartbeat starts, runs, and shuts down cleanly
6. **Kuramoto Synchronization** — Phase coherence across organisms
7. **Mini-Heart / Mini-Brain** — Health vitals and learning state initialized
8. **Cross-Substrate Routing** — Protocol execution routed to correct substrate
9. **Emergence Detection** — Coherence threshold measured across organisms

## Architecture

```
itb/
├── README.md           # This file
├── config.json         # ITB configuration (substrates, organisms, timeouts)
├── run.mjs             # Entry point — runs full ITB
├── harness.mjs         # Multi-runtime substrate test harness
└── reporter.mjs        # Console reporter with pass/fail summary
```

## Configuration

Edit `itb/config.json` to customize:
- Which substrates to exercise
- Number of heartbeat cycles to run
- Emergence threshold
- Timeout limits
