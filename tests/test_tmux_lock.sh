#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

export TERM="${TERM:-tmux-256color}"
export TMUX_LOCK_TEST_ROOT="${TMUX_LOCK_TEST_ROOT:-$ROOT_DIR}"
TEST_USER="${USER:-${LOGNAME:-user}}"
export TMUX_LOCK_TEST_SOCKET="${TMUX_LOCK_TEST_SOCKET:-/tmp/tmux-lock-test-$TEST_USER-$$.sock}"
unset TMUX

cleanup() {
  env -u TMUX tmux -S "$TMUX_LOCK_TEST_SOCKET" kill-server >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

cd "$ROOT_DIR"

echo "Running tmux-lock spec…"
tests/tmux_lock_spec.exp || {
  echo "FAIL!"
  exit 1
}

echo "SUCCESS"
