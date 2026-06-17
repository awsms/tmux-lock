#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
. "$ROOT_DIR/scripts/common.sh"

# first, bring key-table back (so we're not stuck in off)
tmux set -u key-table 2>/dev/null || true   # back to default immediately

# now flip state
setopt @tmux_lock_state off

# restore prefix and normal key processing
restore_prefix
# tmux set -g xterm-keys on 2>/dev/null || true
_switch_root

# restore our saved keys/binds
restore_user_keys
restore_user_binds
restore_global_binds 2>/dev/null || true    # no-op if not using it

# Badge back to origin
status_set_origin
# optionally restore the status bar visibility
status_restore_if_enabled
# Restore a split layout hidden by lock-time zoom.
restore_zoom_if_needed
tmux refresh-client -S
tmux display-message "#[bg=#{@tmux_lock_bar_bg},fg=#{@tmux_lock_passthrough_bg},fill=#{@tmux_lock_bar_bg}]Lock: OFF (tmux active, binds & user-keys restored)"
