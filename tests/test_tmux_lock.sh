#!/usr/bin/env bash
set -euo pipefail

export TERM="${TERM:-tmux-256color}"

echo "Running tmux-lock spec…"
tests/tmux_lock_spec.exp || {
  echo "FAIL!"
  exit 1
}

echo "SUCCESS"
