"use strict";

const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const filters = process.argv.slice(2).map((value) => value.toLowerCase());
const testDir = __dirname;
const files = fs
  .readdirSync(testDir)
  .filter((name) => name.endsWith(".test.js"))
  .filter((name) => {
    if (filters.length === 0) {
      return true;
    }
    const lowerName = name.toLowerCase();
    return filters.some((filter) => lowerName.includes(filter));
  })
  .map((name) => path.join(testDir, name));

if (files.length === 0) {
  console.error(`No test files matched: ${filters.join(", ")}`);
  process.exit(1);
}

const result = spawnSync(process.execPath, ["--test", ...files], {
  stdio: "inherit",
});

process.exit(result.status ?? 1);
