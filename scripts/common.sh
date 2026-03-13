#!/usr/bin/env bash
set -euo pipefail

# target the invoking client if provided by the binder (#{client_tty}).
# if not provided (e.g. tests call scripts via tmux run-shell), pick the first client (some are unused for now)
TGT="${TMUX_LOCK_TARGET:-}"
if [[ -z "$TGT" ]]; then
  TGT="$(tmux list-clients -F '#{client_tty}' 2>/dev/null | head -n1 || true)"
fi
_set()        { if [[ -n "$TGT" ]]; then tmux set     -t "$TGT" "$@"; else tmux set     "$@"; fi; }
_unset()      { if [[ -n "$TGT" ]]; then tmux set -u  -t "$TGT" "$@"; else tmux set -u  "$@"; fi; }
_display()    { if [[ -n "$TGT" ]]; then tmux display -t "$TGT" "$@"; else tmux display "$@"; fi; }
_refresh()    { if [[ -n "$TGT" ]]; then tmux refresh-client -t "$TGT" -S; else tmux refresh-client -S; fi; }
_switch_root(){ if [[ -n "$TGT" ]]; then tmux switch-client -t "$TGT" -T root; else tmux switch-client -T root; fi; }
_switch_off() { if [[ -n "$TGT" ]]; then tmux switch-client -t "$TGT" -T off;  else tmux switch-client -T off;  fi; }

# helpers to read/set global opts
get()    { tmux show -gv "$1"; }
setopt() { tmux set  -g  "$1" "$2"; }

# prefix save/restore
save_prefix() {
  if ! tmux show -gv @tmux_lock_saved_prefix >/dev/null 2>&1 || [ -z "$(tmux show -gv @tmux_lock_saved_prefix)" ]; then
    setopt @tmux_lock_saved_prefix "$(tmux show -gv prefix)"
  fi
}
set_prefix_none() { tmux set -g prefix None; }

restore_prefix() {
  local p; p="$(tmux show -gv @tmux_lock_saved_prefix 2>/dev/null || true)"
  if [ -n "$p" ]; then tmux set -g prefix "$p"; else tmux set -u prefix 2>/dev/null || true; fi
}

# user-keys save/restore
split_words() { local s="${1:-}"; arr=($s); }  # shellcheck disable=SC2206

save_user_keys() {
  split_words "$(get @tmux_lock_user_keys)"
  for idx in "${arr[@]:-}"; do
    if ! tmux show -gv "@tmux_lock_saved_user_key_$idx" >/dev/null 2>&1; then
      val="$(tmux show -sv "user-keys[$idx]" 2>/dev/null || true)"
      setopt "@tmux_lock_saved_user_key_$idx" "$val"
    fi
  done
}

save_user_binds() {
  local all_binds
  all_binds="$(tmux list-keys -T root -F "bind-key #{?key_repeat,-r ,}-T #{key_table} #{key_string} #{key_command}" 2>/dev/null || tmux list-keys -T root)"
  split_words "$(get @tmux_lock_user_keys)"
  for idx in "${arr[@]:-}"; do
    line="$(echo "$all_binds" | sed -n "s/^[[:space:]]*bind-key[[:space:]]\+\(-r \)\?-T root User$idx[[:space:]]\+\(.*\)$/bind-key \1-T root User$idx \2/p" | head -n1 || true)"
    setopt "@tmux_lock_saved_bind_User$idx" "${line:-}"
  done
}

unset_user_keys() {
  split_words "$(get @tmux_lock_user_keys)"
  for idx in "${arr[@]:-}"; do
    tmux set -su "user-keys[$idx]" 2>/dev/null || true
    tmux unbind -T root "User$idx" 2>/dev/null || true
    tmux unbind -n      "User$idx" 2>/dev/null || true
  done
}

restore_user_keys() {
  split_words "$(get @tmux_lock_user_keys)"
  for idx in "${arr[@]:-}"; do
    saved="$(tmux show -gv "@tmux_lock_saved_user_key_$idx" 2>/dev/null || true)"
    if [[ -n "$saved" ]]; then tmux set -s "user-keys[$idx]" "$saved" 2>/dev/null || true
    else tmux set -su "user-keys[$idx]" 2>/dev/null || true; fi
  done
}

restore_user_binds() {
  split_words "$(get @tmux_lock_user_keys)"
  for idx in "${arr[@]:-}"; do
    line="$(tmux show -gv "@tmux_lock_saved_bind_User$idx" 2>/dev/null || true)"
    # [ -n "$line" ] && tmux run-shell "tmux $line" 2>/dev/null || true
    [ -n "$line" ] && tmux source - <<<"$line" 2>/dev/null || true
  done
}

# save/unbind/restore specific -T root keys (@tmux_lock_unbind_keys)
save_unbind_keys() {
  split_words "$(get @tmux_lock_unbind_keys)"
  local i=0 line all_binds
  all_binds="$(tmux list-keys -T root -F "bind-key #{?key_repeat,-r ,}-T #{key_table} #{key_string} #{key_command}" 2>/dev/null || tmux list-keys -T root)"
  for key in "${arr[@]:-}"; do
    # save the full bind line (normalized so we can re-source it later)
    line="$(echo "$all_binds" | sed -n "s/^[[:space:]]*bind-key[[:space:]]\+\(-r \)\?-T root $key[[:space:]]\+\(.*\)$/bind-key \1-T root $key \2/p" | head -n1 || true)"
    setopt "@tmux_lock_saved_unbind_$i" "${line:-}"
    setopt "@tmux_lock_saved_unbind_key_$i" "$key"
    i=$((i+1))
  done
  setopt @tmux_lock_saved_unbind_count "$i"
}

do_unbind_keys() {
  local count key
  count="$(tmux show -gv @tmux_lock_saved_unbind_count 2>/dev/null || echo 0)"
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  for ((i=0; i<count; i++)); do
    key="$(tmux show -gv "@tmux_lock_saved_unbind_key_$i" 2>/dev/null || true)"
    [ -n "$key" ] && {
      tmux unbind -T root "$key" 2>/dev/null || true
      tmux unbind -n      "$key" 2>/dev/null || true
    }
  done
}

restore_global_binds() {
  local count line
  count="$(tmux show -gv @tmux_lock_saved_unbind_count 2>/dev/null || echo 0)"
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  for ((i=0; i<count; i++)); do
    line="$(tmux show -gv "@tmux_lock_saved_unbind_$i" 2>/dev/null || true)"
    [ -n "$line" ] && tmux source - <<<"$line" 2>/dev/null || true
  done
}

# status helpers
status_set_locked()  { tmux set -g status-left "$(tmux show -gv @tmux_lock_block)"; }

# save status-left as origin (but not the LOCKED badge xd)
status_save_origin() {
  local cur badge
  cur="$(tmux show -gv status-left)"
  badge="$(tmux show -gv @tmux_lock_block)"
  if [ "$cur" != "$badge" ]; then
    tmux set -g @tmux_lock_orig_left "$cur"
  fi
}

status_set_origin()  { tmux set -g status-left "$(tmux show -gv @tmux_lock_orig_left)"; }

# verify helpers
verify_off_table()      { local t="${TMUX_LOCK_TARGET:-}"; [ "$(tmux display -t "$t" -p '#{client_key_table}')" = "off" ]; }
verify_not_off_table()  { local t="${TMUX_LOCK_TARGET:-}"; [ "$(tmux display -t "$t" -p '#{client_key_table}')" != "off" ]; }


# status bar hide/restore stuff
# truthy check for tmux string options (1/true/yes/on)
is_truthy() {
  local v
  v="$(get "$1" | tr '[:upper:]' '[:lower:]' 2>/dev/null || true)"
  case "$v" in
    1|true|yes|on) return 0 ;;
    *)             return 1 ;;
  esac
}

# Save current global 'status' value so we can restore it exactly
status_save_visible_flag() {
  # only write once per lock cycle
  if ! tmux show -gv @tmux_lock_orig_status >/dev/null 2>&1 || [ -z "$(tmux show -gv @tmux_lock_orig_status)" ]; then
    setopt @tmux_lock_orig_status "$(tmux show -gv status)"
  fi
}

status_hide_if_enabled() {
  if is_truthy @tmux_hide_status_onlock; then status_save_visible_flag; tmux set -g status off; fi
}

status_restore_if_enabled() {
  if is_truthy @tmux_hide_status_onlock; then
    local s; s="$(tmux show -gv @tmux_lock_orig_status 2>/dev/null || true)"
    if [ -n "$s" ]; then tmux set -g status "$s"; else tmux set -g status on; fi
    tmux set -g @tmux_lock_orig_status "" 2>/dev/null || true
  fi
}