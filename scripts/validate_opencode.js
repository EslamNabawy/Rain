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

function parseFrontMatter(abs) {
  try {
    const text = fs.readFileSync(abs, 'utf8');
    const lines = text.split(/\r?\n/);
    const start = lines.indexOf('---');
    if (start >= 0) {
      const endIdx = lines.indexOf('---', start + 1);
      if (endIdx > start) {
        const block = lines.slice(start + 1, endIdx).join('\n');
        const map = {};
        block.split(/\n/).forEach(l => {
          const m = l.match(/^(\s*\w+)\s*:\s*(.*)$/);
          if (m) {
            map[m[1].trim()] = m[2].trim();
          }
        });
        return map;
      }
    }
  } catch {
    // ignore
  }
  return null;
}

function validateSkillPath(skillPath) {
  const abs = path.resolve(__dirname, '..', skillPath);
  if (!fileExists(abs)) {
    return { ok: false, reason: `Missing skill file: ${abs}` };
  }
  const fm = parseFrontMatter(abs);
  const hasName = !!(fm && fm.name);
  const hasDescription = !!(fm && fm.description);
  // Return both flags for a richer report (but keep compatibility)
  return { ok: true, path: skillPath, hasName, hasDescription };
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
    if (!r.ok) {
      issues.push(r.reason);
    } else {
      if (!r.hasName || !r.hasDescription) {
        issues.push(`Skill file ${r.path} missing required front-matter (name/description)`);
      }
    }
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
