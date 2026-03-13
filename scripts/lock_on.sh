#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
. "$ROOT_DIR/scripts/common.sh"

# Flip state first
setopt @tmux_lock_state on

# Cancel copy-mode etc. (so table flip takes immediately)
if [ "$(_display -p '#{pane_in_mode}')" = "1" ]; then
  tmux send-keys -X cancel
fi

# Disable prefix immediately to avoid tmux eating any part of the trigger chord
save_prefix
tmux set -g prefix None

# Turn CSI passthrough on (raw to app)
# tmux set -g xterm-keys off
_switch_off

# save & remove things we manage
save_user_keys
save_user_binds
save_unbind_keys
unset_user_keys
do_unbind_keys

# put the session/client into passthrough mode
tmux set -u key-table               2>/dev/null || true     # clear any previous override
tmux set    key-table off                                   # current client/session only

# saving the original badge
status_save_origin

# setting the locked one
status_set_locked
# optionally hide the status bar entirely while locked
status_hide_if_enabled
tmux refresh-client -S
tmux display-message "#[bg=#{@tmux_lock_passthrough_bg},fg=#{@tmux_lock_p_text_color},fill=#{@tmux_lock_passthrough_bg}]Lock: ON (raw keys will be sent to remote/nested tmux/program)"
