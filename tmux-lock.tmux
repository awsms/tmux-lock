#!/usr/bin/env bash
# tmux-lock: simple lock using the session/client key-table option
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# defaults (only if not already set)
def() { local k="$1" v="$2"; local cur; cur="$(tmux show -gv "$k" 2>/dev/null || true)"; [ -n "$cur" ] || tmux set -g "$k" "$v"; }
def @tmux_lock_toggle_key       'C-Space'
def @tmux_lock_state            'off'
def @tmux_lock_passthrough_bg   '#f7768e'
def @tmux_lock_bar_bg           '#292e42'
def @tmux_lock_p_text_color     '#ffffff'
def @tmux_lock_user_keys        ''
def @tmux_lock_unbind_keys      'C-S-Left C-S-Right C-S-Up C-S-Down C-Pageup C-Pagedown'
def @tmux_lock_rescue_key       'M-Escape'
def @tmux_hide_status_onlock    'false'
def @tmux_lock_auto_commands    ''
def @tmux_lock_auto_interval    '1'
def @tmux_lock_zoom_pane_onlock 'true'

# locked badge
tmux set -g @tmux_lock_block '#[bg=#{@tmux_lock_passthrough_bg}]#[fg=#{@tmux_lock_p_text_color}]#[bold] LOCKED #[bg=#{@tmux_lock_bar_bg}]#[fg=#{@tmux_lock_passthrough_bg}]#[default]'

# bindings - synchronous (no -b), so no races
k="$(tmux show -gv @tmux_lock_toggle_key)"
rescue_k="$(tmux show -gv @tmux_lock_rescue_key)"

tmux unbind -T root "$k" 2>/dev/null || true
tmux bind   -T root "$k" "run-shell 'TMUX_LOCK_TARGET=#{client_tty} ${CURRENT_DIR}/scripts/lock_on.sh'"

tmux unbind -T off "$k" 2>/dev/null || true
tmux bind   -T off  "$k" "run-shell 'TMUX_LOCK_TARGET=#{client_tty} ${CURRENT_DIR}/scripts/lock_off.sh'"

tmux unbind -T root "$rescue_k" 2>/dev/null || true
tmux bind   -T root "$rescue_k"  "run-shell 'TMUX_LOCK_TARGET=#{client_tty} ${CURRENT_DIR}/scripts/lock_off.sh'"
tmux unbind -T off  "$rescue_k"  2>/dev/null || true
tmux bind   -T off  "$rescue_k"  "run-shell 'TMUX_LOCK_TARGET=#{client_tty} ${CURRENT_DIR}/scripts/lock_off.sh'"

tmux unbind -T root MouseDown1StatusLeft 2>/dev/null || true
tmux bind   -T root MouseDown1StatusLeft \
"if-shell -F '#{==:#{@tmux_lock_state},on}' 'run-shell \"TMUX_LOCK_TARGET=#{client_tty} ${CURRENT_DIR}/scripts/lock_off.sh\"' ''"
tmux unbind -T off  MouseDown1StatusLeft 2>/dev/null || true
tmux bind   -T off  MouseDown1StatusLeft \
"if-shell -F '#{==:#{@tmux_lock_state},on}' 'run-shell \"TMUX_LOCK_TARGET=#{client_tty} ${CURRENT_DIR}/scripts/lock_off.sh\"' ''"

# Start the auto-lock monitor only when commands are configured.
if [ -n "$(tmux show -gv @tmux_lock_auto_commands 2>/dev/null || true)" ]; then
  tmux run-shell -b "'${CURRENT_DIR}/scripts/auto_lock.sh' start"
fi
