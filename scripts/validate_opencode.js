#!/usr/bin/env node
// Lightweight validator for opencode.json and the referenced SKILL.md files
// Usage: node scripts/validate_opencode.js

const fs = require('fs');
const path = require('path');

function readJson(p) {
  const text = fs.readFileSync(p, 'utf8');
  return JSON.parse(text);
}

function fileExists(p) {
  try {
    return fs.statSync(p).isFile();
  } catch {
    return false;
  }
}

function readFirstLine(p) {
  try {
    const data = fs.readFileSync(p, 'utf8');
    const firstLine = data.split(/\r?\n/)[0];
    return firstLine;
  } catch {
    return '';
  }
}

function validateSkillPath(skillPath) {
  const abs = path.resolve(__dirname, '..', skillPath);
  if (!fileExists(abs)) {
    return { ok: false, reason: `Missing skill file: ${abs}` };
  }
  // Quick sanity: ensure it's a SKILL.md-ish file
  const extOk = /SKILL\.md$/i.test(abs);
  if (!_extOk) {
    // We don't fail hard on extension, but log a warning
  }
  // Basic content check: expect a 'name:' header somewhere
  const content = readFirstLine(abs);
  const hasName = /name\s*:/i.test(content) || /#\s*Skill|Description:/i.test(content);
  return { ok: true, path: skillPath, hasName };
}

function main() {
  const opencodePath = path.resolve(__dirname, '..', 'opencode.json');
  if (!fileExists(opencodePath)) {
    console.error(`ERROR: opencode.json not found at ${opencodePath}`);
    process.exit(2);
  }

  let config;
  try {
    config = readJson(opencodePath);
  } catch (e) {
    console.error(`ERROR: Failed to parse opencode.json: ${e.message}`);
    process.exit(3);
  }

  const model = config?.model;
  const instructions = Array.isArray(config?.instructions) ? config.instructions : [];

  let issues = [];
  if (!model || typeof model !== 'string') {
    issues.push('Invalid or missing: model');
  }
  if (!instructions.length) {
    issues.push('Invalid or missing: instructions (should be a non-empty array)');
  }

  const results = instructions.map((p) => validateSkillPath(p));
  results.forEach((r) => {
    if (!r.ok) issues.push(r.reason);
  });

  // Summary
  console.log('OPENCODE VALIDATION SUMMARY');
  console.log(`Model: ${model || 'MISSING'}`);
  console.log(`Skills referenced: ${instructions.length}`);
  console.log(`Status: ${issues.length ? 'FAIL' : 'PASS'}`);
  if (issues.length) {
    console.log('Issues:');
    issues.forEach((i, idx) => console.log(` ${idx + 1}. ${i}`));
  } else {
    console.log('All referenced skills found and superficially valid.');
  }

  // Exit code: 0 for pass, 1 for soft fail, 2 for hard fail
  process.exit(issues.length ? 1 : 0);
}

main();
