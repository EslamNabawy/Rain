#!/usr/bin/env node
/* Phase 2 Runner: Simulates execution of Phase 2 units (Planner, Architect, Backend, Frontend, Database, Gatekeeping).
 * Usage:
 *   node scripts/phase2-runner.js [--fail-unit N]
 * Where N is 1-6 to simulate a failure in Unit N (1-based index).
 */
const fs = require('fs');
const path = require('path');

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

const units = [
  { id: 'unit-01', name: 'Planner Decomposition' },
  { id: 'unit-02', name: 'Architect Interfaces' },
  { id: 'unit-03', name: 'Backend Skeleton' },
  { id: 'unit-04', name: 'Frontend Skeleton' },
  { id: 'unit-05', name: 'Database Skeleton' },
  { id: 'unit-06', name: 'Gatekeeping & Evaluation' },
];

let failUnit = null;
const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--fail-unit' && i + 1 < args.length) {
    failUnit = parseInt(args[i + 1], 10);
  }
}

async function run() {
  console.log('[Phase 2 Runner] Starting simulation of Phase 2 units...');
  const results = [];
  for (let idx = 0; idx < units.length; idx++) {
    const unit = units[idx];
    const num = idx + 1;
    console.log(`- Running ${unit.name} (${unit.id})`);
    await sleep(120); // simulate work
    const shouldFail = failUnit !== null && failUnit === num;
    if (shouldFail) {
      const reason = 'Simulated failure for testing gating';
      results.push({ unit: unit.id, name: unit.name, status: 'FAILED', reason });
      console.log(`  FAILED: ${unit.name} due to simulated error`);
      // Stop on first failure to mimic gating behavior
      break;
    } else {
      results.push({ unit: unit.id, name: unit.name, status: 'COMPLETED', reason: '' });
      console.log(`  COMPLETED: ${unit.name}`);
    }
  }

  const summary = {
    total: units.length,
    completed: results.filter(r => r.status === 'COMPLETED').length,
    failed: results.filter(r => r.status === 'FAILED').length,
    details: results
  };

  const artifactPath = path.resolve(process.cwd(), 'plans/phase2-runner-output.json');
  const payload = {
    timestamp: new Date().toISOString(),
    summary,
  };
  try {
    fs.writeFileSync(artifactPath, JSON.stringify(payload, null, 2));
    console.log(`
Phase 2 run artifact written to ${artifactPath}`);
  } catch (e) {
    console.error('Failed to write artifact', e);
  }
}

run();
