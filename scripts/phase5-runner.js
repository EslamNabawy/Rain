#!/usr/bin/env node
// Phase 5 PR content generator: aggregates Phase 2-4 artifacts into a PR body
const fs = require('fs');
const path = require('path');

function json(pathStr){ return JSON.parse(fs.readFileSync(pathStr, 'utf8')); }

function readPlan(planPath){ try{ return fs.readFileSync(planPath,'utf8'); }catch{ return ''; } }

function main(){
  const t2 = path.resolve(process.cwd(), 'plans', 'phase2-runner-output.json');
  const t3 = path.resolve(process.cwd(), 'plans', 'phase3-runner-output.json');
  const t4 = path.resolve(process.cwd(), 'plans', 'phase4-runner-output.json');
  const parts = [];
  parts.push('# OpenCode Phase 5 Delivery');
  if(fs.existsSync(t2)) parts.push('- Phase 2: Phase 2 run available: '+t2);
  if(fs.existsSync(t3)) parts.push('- Phase 3: Phase 3 run available: '+t3);
  if(fs.existsSync(t4)) parts.push('- Phase 4: Phase 4 run available: '+t4);
  // Append plan link
  const plan = path.resolve(process.cwd(), 'plans', 'phase5-delivery.md');
  if (fs.existsSync(plan)) {
    parts.push('\nPlan Reference: ' + plan);
  }
  const body = parts.join('\n');
  console.log(body);
}

main();
