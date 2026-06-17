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
load_root_binds() {
  if [ "${tmux_lock_root_binds_loaded:-0}" != "1" ]; then
    tmux_lock_root_binds="$(tmux list-keys -T root -F "bind-key #{?key_repeat,-r ,}-T #{key_table} #{key_string} #{key_command}" 2>/dev/null || tmux list-keys -T root)"
    tmux_lock_root_binds_loaded=1
  fi
}
find_root_bind() {
  local key="$1" line
  load_root_binds
  while IFS= read -r line; do
    case "$line" in
      bind-key*" -T root $key "*)
        printf '%s\n' "$line"
        return 0
        ;;
    esac
  done <<< "$tmux_lock_root_binds"
}
normalise_key_alias() {
  case "$1" in
    Pageup) printf '%s\n' PPage ;;
    Pagedown) printf '%s\n' NPage ;;
    *-Pageup) printf '%s-PPage\n' "${1%-Pageup}" ;;
    *-Pagedown) printf '%s-NPage\n' "${1%-Pagedown}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

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
  local cmd=() line
  split_words "$(get @tmux_lock_user_keys)"
  for idx in "${arr[@]:-}"; do
    line="$(find_root_bind "User$idx")"
    [ "${#cmd[@]}" -gt 0 ] && cmd+=(\;)
    cmd+=(set-option -gq "@tmux_lock_saved_bind_User$idx" "${line:-}")
  done
  [ "${#cmd[@]}" -gt 0 ] && tmux "${cmd[@]}" 2>/dev/null || true
}

unset_user_keys() {
  local cmd=()
  split_words "$(get @tmux_lock_user_keys)"
  for idx in "${arr[@]:-}"; do
    [ "${#cmd[@]}" -gt 0 ] && cmd+=(\;)
    cmd+=(set-option -q -su "user-keys[$idx]")
    cmd+=(\; unbind-key -q -T root "User$idx")
    cmd+=(\; unbind-key -q -n "User$idx")
  done
  [ "${#cmd[@]}" -gt 0 ] && tmux "${cmd[@]}" 2>/dev/null || true
}

restore_user_keys() {
  local cmd=()
  split_words "$(get @tmux_lock_user_keys)"
  for idx in "${arr[@]:-}"; do
    saved="$(tmux show -gv "@tmux_lock_saved_user_key_$idx" 2>/dev/null || true)"
    [ "${#cmd[@]}" -gt 0 ] && cmd+=(\;)
    if [[ -n "$saved" ]]; then
      cmd+=(set-option -q -s "user-keys[$idx]" "$saved")
    else
      cmd+=(set-option -q -s -u "user-keys[$idx]")
    fi
  done
  [ "${#cmd[@]}" -gt 0 ] && tmux "${cmd[@]}" 2>/dev/null || true
}

restore_user_binds() {
  local script=""
  split_words "$(get @tmux_lock_user_keys)"
  for idx in "${arr[@]:-}"; do
    line="$(tmux show -gv "@tmux_lock_saved_bind_User$idx" 2>/dev/null || true)"
    # [ -n "$line" ] && tmux run-shell "tmux $line" 2>/dev/null || true
    [ -n "$line" ] && script+="$line"$'\n'
  done
  [ -n "$script" ] && tmux source - <<<"$script" 2>/dev/null || true
}

# save/unbind/restore specific -T root keys (@tmux_lock_unbind_keys)
save_unbind_keys() {
  local cmd=()
  split_words "$(get @tmux_lock_unbind_keys)"
  local i=0 line norm_key
  for key in "${arr[@]:-}"; do
    # Normalize common tmux aliases like C-Pageup -> C-PPage.
    norm_key="$(normalise_key_alias "$key")"

    # save the full bind line (normalized so we can re-source it later)
    line="$(find_root_bind "$norm_key")"
    
    # fallback: if we couldn't find the normalized key, try the original key name
    if [[ -z "$line" && "$norm_key" != "$key" ]]; then
       line="$(find_root_bind "$key")"
    fi

    [ "${#cmd[@]}" -gt 0 ] && cmd+=(\;)
    cmd+=(set-option -gq "@tmux_lock_saved_unbind_$i" "${line:-}")
    cmd+=(\; set-option -gq "@tmux_lock_saved_unbind_key_$i" "$key")
    i=$((i+1))
  done
  [ "${#cmd[@]}" -gt 0 ] && cmd+=(\;)
  cmd+=(set-option -gq @tmux_lock_saved_unbind_count "$i")
  tmux "${cmd[@]}" 2>/dev/null || true
}

do_unbind_keys() {
  local count key cmd=()
  count="$(tmux show -gv @tmux_lock_saved_unbind_count 2>/dev/null || echo 0)"
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  for ((i=0; i<count; i++)); do
    key="$(tmux show -gv "@tmux_lock_saved_unbind_key_$i" 2>/dev/null || true)"
    [ -n "$key" ] || continue
    [ "${#cmd[@]}" -gt 0 ] && cmd+=(\;)
    cmd+=(unbind-key -q -T root "$key")
    cmd+=(\; unbind-key -q -n "$key")
  done
  [ "${#cmd[@]}" -gt 0 ] && tmux "${cmd[@]}" 2>/dev/null || true
}

restore_global_binds() {
  local count line script=""
  count="$(tmux show -gv @tmux_lock_saved_unbind_count 2>/dev/null || echo 0)"
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  for ((i=0; i<count; i++)); do
    line="$(tmux show -gv "@tmux_lock_saved_unbind_$i" 2>/dev/null || true)"
    [ -n "$line" ] && script+="$line"$'\n'
  done
  [ -n "$script" ] && tmux source - <<<"$script" 2>/dev/null || true
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

# Pane zoom helpers. If locking from a split window, zoom the locked pane so the
# local tmux chrome gets out of the way, then restore only zooms we created.
zoom_pane_if_enabled() {
  is_truthy @tmux_lock_zoom_pane_onlock || return 0

  local pane panes zoomed
  pane="$(_display -p '#{pane_id}')"
  panes="$(_display -p '#{window_panes}')"
  zoomed="$(_display -p '#{window_zoomed_flag}')"

  setopt @tmux_lock_zoomed_on_lock off
  setopt @tmux_lock_zoom_pane "$pane"

  if [[ "$panes" =~ ^[0-9]+$ ]] && [ "$panes" -gt 1 ] && [ "$zoomed" = "0" ]; then
    tmux resize-pane -Z -t "$pane"
    setopt @tmux_lock_zoomed_on_lock on
  fi
}

restore_zoom_if_needed() {
  is_truthy @tmux_lock_zoom_pane_onlock || return 0
  is_truthy @tmux_lock_zoomed_on_lock || return 0

  local pane zoomed
  pane="$(tmux show -gv @tmux_lock_zoom_pane 2>/dev/null || true)"
  if [ -n "$pane" ]; then
    zoomed="$(tmux display -pt "$pane" '#{window_zoomed_flag}' 2>/dev/null || true)"
    if [ "$zoomed" = "1" ]; then
      tmux resize-pane -Z -t "$pane"
    fi
  fi

  setopt @tmux_lock_zoomed_on_lock off
  setopt @tmux_lock_zoom_pane ""
}
