#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const repoRoot = path.resolve(__dirname, '..');
const outputPath = path.join(repoRoot, 'plans', 'phase4-runner-output.json');

const checks = [
  {
    name: 'Flutter analyze app',
    command: 'flutter',
    args: ['analyze'],
    cwd: 'apps/rain',
  },
  {
    name: 'App tests',
    command: 'flutter',
    args: ['test'],
    cwd: 'apps/rain',
  },
  {
    name: 'Peer core tests',
    command: 'flutter',
    args: ['test'],
    cwd: 'packages/peer_core',
  },
  {
    name: 'Protocol brain tests',
    command: 'flutter',
    args: ['test'],
    cwd: 'packages/protocol_brain',
  },
  {
    name: 'Rain core tests',
    command: 'flutter',
    args: ['test'],
    cwd: 'packages/rain_core',
  },
];

function resolveWindowsFlutterCommand(args) {
  const whereResult = spawnSync('where.exe', ['flutter'], {
    encoding: 'utf8',
  });
  const candidates = whereResult.stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  const flutterPath = candidates.find((line) => line.toLowerCase().endsWith('.bat'))
    || candidates[0]
    || 'flutter.bat';
  return {
    command: 'powershell.exe',
    args: [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      `& "${flutterPath}" ${args.join(' ')}`,
    ],
  };
}

function runCheck(check) {
  const cwd = path.join(repoRoot, check.cwd);
  const commandLine = [check.command, ...check.args].join(' ');
  const resolved = process.platform === 'win32' && check.command === 'flutter'
    ? resolveWindowsFlutterCommand(check.args)
    : { command: check.command, args: check.args };
  console.log(`[Phase 4 Runner] ${check.name}: ${commandLine} (${check.cwd})`);

  const result = spawnSync(resolved.command, resolved.args, {
    cwd,
    stdio: 'inherit',
  });
  const exitCode = typeof result.status === 'number' ? result.status : 1;
  const passed = exitCode === 0;

  return {
    name: check.name,
    command: commandLine,
    cwd: check.cwd,
    status: passed ? 'PASS' : 'FAIL',
    exitCode,
    error: result.error ? result.error.message : '',
  };
}

function main() {
  console.log('[Phase 4 Runner] Starting real Flutter verification.');
  const details = checks.map(runCheck);
  const summary = {
    total: details.length,
    passed: details.filter((check) => check.status === 'PASS').length,
    failed: details.filter((check) => check.status === 'FAIL').length,
  };
  const artifact = {
    timestamp: new Date().toISOString(),
    summary,
    details,
  };

  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, `${JSON.stringify(artifact, null, 2)}\n`);
  console.log(`[Phase 4 Runner] Artifact written to ${outputPath}`);

  if (summary.failed > 0) {
    process.exit(1);
  }
}

main();
