#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
action="${1:-toggle}"

case "$action" in
  on)
    exec "$ROOT_DIR/scripts/lock_on.sh"
    ;;
  off)
    exec "$ROOT_DIR/scripts/lock_off.sh"
    ;;
  toggle)
    state="$(tmux show -gv @tmux_lock_state 2>/dev/null || true)"
    if [ "$state" = "on" ]; then
      exec "$ROOT_DIR/scripts/lock_off.sh"
    else
      exec "$ROOT_DIR/scripts/lock_on.sh"
    fi
    ;;
  *)
    echo "usage: $0 [on|off|toggle]" >&2
    exit 2
    ;;
esac
