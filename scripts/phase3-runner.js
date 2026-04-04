#!/usr/bin/env node
/* Phase 3 Runner: Lightweight integration harness simulating end-to-end wiring across Phase 2 skeletons.
 * Usage:
 *   node scripts/phase3-runner.js [--fail-unit N]
 * N: 1-6 to simulate a failure in that unit; 0 or omitted means all succeed.
 */
const fs = require('fs');
const path = require('path');
function sleep(ms){ return new Promise(r => setTimeout(r, ms)); }

const units = [
  { id: 'unit-01', name: 'Planner Decomposition' },
  { id: 'unit-02', name: 'Architect Interfaces' },
  { id: 'unit-03', name: 'Backend Skeleton' },
  { id: 'unit-04', name: 'Frontend Skeleton' },
  { id: 'unit-05', name: 'Database Skeleton' },
  { id: 'unit-06', name: 'Gatekeeping & Evaluation' },
];
let failUnit = 0;
const args = process.argv.slice(2);
for (let i=0;i<args.length;i++){
  if (args[i] === '--fail-unit' && i+1<args.length){ failUnit = parseInt(args[i+1], 10); }
}
async function run(){
  console.log('[Phase 3 Runner] Starting integration simulation...');
  // Load Phase 2 outcome if available to reflect status
  let phase2 = null; try { phase2 = require(path.resolve(process.cwd(), 'plans', 'phase2-runner-output.json')); } catch { phase2 = null; }
  const details = [];
  let completedCount = 0;
  for (let i=0;i<units.length;i++){
    const u = units[i];
    const idx = i+1;
    console.log(`- Integrating ${u.name} (${u.id})`);
    await sleep(100);
    if (failUnit === idx){
      details.push({ unit: u.id, name: u.name, status: 'FAILED', reason: 'Simulated integration failure' });
      console.log(`  FAILED: ${u.name}`);
      break;
    } else {
      details.push({ unit: u.id, name: u.name, status: 'COMPLETED', reason: '' });
      completedCount++;
      console.log(`  COMPLETED: ${u.name}`);
    }
  }
  const summary = {
    total: units.length,
    completed: details.filter(d => d.status === 'COMPLETED').length,
    failed: details.filter(d => d.status === 'FAILED').length,
  };
  const artifact = {
    timestamp: new Date().toISOString(),
    summary,
    details
  };
  const outPath = path.resolve(process.cwd(), 'plans', 'phase3-runner-output.json');
  fs.writeFileSync(outPath, JSON.stringify(artifact, null, 2));
  console.log(`Phase 3 run artifact written to ${outPath}`);
}
run();
