#!/usr/bin/env node
// Validate Phase 4 output artifact to gate PRs
const fs = require('fs');
const path = require('path');
try {
  const p = path.resolve(process.cwd(), 'plans', 'phase4-runner-output.json');
  const data = JSON.parse(fs.readFileSync(p, 'utf8'));
  const s = data?.summary ?? {};
  let ok = true;
  if ('total' in s) {
    const total = Number(s.total);
    const passed = Number(s.passed ?? s.completed ?? 0);
    ok = total > 0 ? passed === total : true;
  } else {
    // Fallback: ensure details exist and all statuses PASS
    ok = Array.isArray(data?.details) && data.details.every(d => d.status === 'PASS' || d.status === 'COMPLETED');
  }
  if (ok) {
    console.log('Phase 4 verification: PASS');
    process.exit(0);
  } else {
    console.error('Phase 4 verification: FAIL');
    process.exit(1);
  }
} catch (e) {
  console.error('Phase 4 verification: ERROR', e?.message ?? e);
  process.exit(2);
}
