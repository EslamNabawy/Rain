#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

function fail(message, code = 1) {
  console.error(`Phase 4 verification: FAIL - ${message}`);
  process.exit(code);
}

try {
  const artifactPath = path.resolve(
    process.cwd(),
    'plans',
    'phase4-runner-output.json',
  );
  const data = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
  const details = data.details;
  const summary = data.summary;

  if (!Array.isArray(details) || details.length === 0) {
    fail('artifact has no check details', 2);
  }
  if (!summary || Number(summary.total) !== details.length) {
    fail('summary total does not match detail count', 2);
  }

  const failures = details.filter((detail) => detail.status !== 'PASS');
  if (failures.length > 0) {
    const names = failures.map((detail) => detail.name).join(', ');
    fail(`failed checks: ${names}`);
  }

  if (Number(summary.passed) !== details.length || Number(summary.failed) !== 0) {
    fail('summary pass/fail counts are inconsistent', 2);
  }

  console.log('Phase 4 verification: PASS');
} catch (error) {
  fail(error?.message ?? error, 2);
}
