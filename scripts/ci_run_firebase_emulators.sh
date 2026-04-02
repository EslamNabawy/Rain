#!/usr/bin/env bash
set -euo pipefail

echo "[CI] Starting Firebase emulators (Auth + RTDB) for tests..."

if ! command -v firebase >/dev/null 2>&1; then
  echo "[CI] Installing firebase-tools..."
  npm install -g firebase-tools
fi

firebase --version

export EMULATORS_LOG="firebase_emulators.log"
> "$EMULATORS_LOG" 2>&1

# Start emulators in background
firebase emulators:start --project RainMVP --only auth,database --host 127.0.0.1 > "$EMULATORS_LOG" 2>&1 &
EMULATORS_PID=$!

echo "[CI] Emulators started with PID $EMULATORS_PID. Waiting for readiness..."

set +e
RETRIES=0
MAX_RETRIES=60
while [ $RETRIES -lt $MAX_RETRIES ]; do
  if curl -sSf http://127.0.0.1:9000/.json >/dev/null 2>&1; then
    break
  fi
  sleep 1
  RETRIES=$((RETRIES+1))
done
set -e

if [ $RETRIES -eq $MAX_RETRIES ]; then
  echo "[CI] Firebase emulators did not become ready in time. Check logs: $EMULATORS_LOG"
  kill $EMULATORS_PID || true
  exit 1
fi

echo "[CI] Emulators ready. Running tests..."
echo "FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099" >> $GITHUB_ENV
echo "FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9000" >> $GITHUB_ENV

trap 'echo "[CI] Stopping emulators"; kill $EMULATORS_PID' EXIT

# Optionally run tests if RUN_TESTS is set (defaults to true in CI)
if [ "${RUN_TESTS:-true}" = "true" ]; then
  echo "[CI] Running tests (melos bootstrap & melos test)..."
  melos bootstrap
  melos test
  TEST_STATUS=$?
  if [ $TEST_STATUS -ne 0 ]; then
    echo "[CI] Tests failed with status $TEST_STATUS"
    kill $EMULATORS_PID || true
    exit $TEST_STATUS
  fi
fi
