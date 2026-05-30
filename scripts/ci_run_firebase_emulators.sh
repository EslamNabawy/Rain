#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIREBASE_DIR="$REPO_ROOT/backend/firebase"
FIREBASE_CONFIG="$FIREBASE_DIR/firebase.json"
FIREBASE_TOOLS_VERSION="${FIREBASE_TOOLS_VERSION:-15.18.0}"

echo "[CI] Starting Firebase emulators (Auth + RTDB) for tests..."

if ! command -v node >/dev/null 2>&1 &&
  command -v node.exe >/dev/null 2>&1 &&
  command -v powershell.exe >/dev/null 2>&1 &&
  command -v wslpath >/dev/null 2>&1; then
  echo "[CI] Detected WSL shell with Windows Node.js; delegating to PowerShell runner."
  POWERSHELL_SCRIPT="$(wslpath -w "$REPO_ROOT/scripts/ci_run_firebase_emulators.ps1")"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
    "\$env:RUN_TESTS='${RUN_TESTS:-true}'; \$env:FIREBASE_TOOLS_VERSION='$FIREBASE_TOOLS_VERSION'; & '$POWERSHELL_SCRIPT'"
  exit $?
fi

NODE_WRAPPER_DIR=""
cleanup() {
  if [ -n "$NODE_WRAPPER_DIR" ] && [ -d "$NODE_WRAPPER_DIR" ]; then
    rm -rf "$NODE_WRAPPER_DIR"
  fi
}
trap cleanup EXIT

if ! command -v node >/dev/null 2>&1; then
  if command -v node.exe >/dev/null 2>&1; then
    NODE_WRAPPER_DIR="$(mktemp -d)"
    {
      printf '%s\n' '#!/usr/bin/env bash'
      printf '%s\n' 'args=()'
      printf '%s\n' 'for arg in "$@"; do'
      printf '%s\n' '  if command -v wslpath >/dev/null 2>&1 && [ "${arg#/mnt/}" != "$arg" ]; then'
      printf '%s\n' '    args+=("$(wslpath -w "$arg")")'
      printf '%s\n' '  else'
      printf '%s\n' '    args+=("$arg")'
      printf '%s\n' '  fi'
      printf '%s\n' 'done'
      printf '%s\n' 'exec node.exe "${args[@]}"'
    } > "$NODE_WRAPPER_DIR/node"
    chmod +x "$NODE_WRAPPER_DIR/node"
    export PATH="$NODE_WRAPPER_DIR:$PATH"
    echo "[CI] Added temporary node shim for Windows/WSL shell interop."
  else
    echo "[CI] Node.js is required but was not found on PATH."
    exit 1
  fi
fi

if ! command -v firebase >/dev/null 2>&1; then
  echo "[CI] Installing firebase-tools..."
  npm install -g "firebase-tools@$FIREBASE_TOOLS_VERSION"
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

echo "[CI] Running Firebase emulator integration tests..."
firebase --config "$FIREBASE_CONFIG" emulators:exec \
  --project rain-8fb4b \
  --only auth,database \
  --non-interactive \
  "dart pub get && cd apps/rain && flutter pub get && flutter test test/integration_two_users_end2end_test.dart --dart-define=RUN_RAIN_INTEGRATION_TESTS=true --reporter expanded && flutter test test/integration_two_devices_handshake_full_test.dart --dart-define=RUN_RAIN_INTEGRATION_TESTS=true --reporter expanded && flutter test test/integration_voice_signaling_emulator_test.dart --dart-define=RUN_RAIN_INTEGRATION_TESTS=true --reporter expanded"
