#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIREBASE_DIR="$REPO_ROOT/backend/firebase"
FIREBASE_CONFIG="$FIREBASE_DIR/firebase.json"

echo "[CI] Starting Firebase emulators (Auth + RTDB) for tests..."

if ! command -v firebase >/dev/null 2>&1; then
  echo "[CI] Installing firebase-tools..."
  npm install -g firebase-tools
fi

firebase --version

cd "$REPO_ROOT"

if [ ! -f "$FIREBASE_CONFIG" ]; then
  echo "[CI] Firebase config not found: $FIREBASE_CONFIG"
  exit 1
fi

if [ "${RUN_TESTS:-true}" != "true" ]; then
  echo "[CI] RUN_TESTS is disabled; skipping emulator test run."
  exit 0
fi

echo "[CI] Running tests inside Firebase emulator session..."
firebase --config "$FIREBASE_CONFIG" emulators:exec \
  --project rain-8fb4b \
  --only auth,database \
  --non-interactive \
  "melos bootstrap && melos run test"
