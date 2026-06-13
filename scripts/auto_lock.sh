#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"

opt() { tmux show -gv "$1" 2>/dev/null || true; }
setopt() { tmux set -g "$1" "$2" 2>/dev/null || true; }

normalise_commands() {
  printf '%s\n' "${1:-}" | sed 's/[][]/ /g; s/[",]/ /g; s/'"'"'/ /g'
}

has_commands() {
  local raw="${1:-}" item
  for item in $(normalise_commands "$raw"); do
    [ -n "$item" ] && return 0
  done
  return 1
}

command_matches() {
  local current="${1:-}" raw="${2:-}" item current_base item_base
  [ -n "$current" ] || return 1
  current_base="${current##*/}"

  for item in $(normalise_commands "$raw"); do
    item_base="${item##*/}"
    if [ "$current" = "$item" ] || [ "$current_base" = "$item_base" ]; then
      return 0
    fi
  done

  return 1
}

auto_interval() {
  local interval
  interval="$(opt @tmux_lock_auto_interval)"
  if [[ ! "$interval" =~ ^[0-9]+$ ]] || [ "$interval" -lt 1 ]; then
    interval=1
  fi
  printf '%s\n' "$interval"
}

pid_is_running() {
  local pid
  pid="$(opt @tmux_lock_auto_monitor_pid)"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  [ "$pid" != "$$" ] || return 1
  kill -0 "$pid" 2>/dev/null
}

clear_monitor_pid() {
  local pid
  pid="$(opt @tmux_lock_auto_monitor_pid)"
  if [ "$pid" = "$$" ]; then
    setopt @tmux_lock_auto_monitor_pid ""
  fi
}

clear_auto_active() {
  setopt @tmux_lock_auto_active off
  setopt @tmux_lock_auto_pane ""
  setopt @tmux_lock_auto_target ""
  setopt @tmux_lock_auto_command ""
}

clear_suppression() {
  setopt @tmux_lock_auto_suppressed_pane ""
  setopt @tmux_lock_auto_suppressed_command ""
}

pane_command() {
  local pane="${1:-}"
  [ -n "$pane" ] || return 0
  tmux display-message -p -t "$pane" '#{pane_current_command}' 2>/dev/null || true
}

client_exists() {
  local target="${1:-}"
  [ -n "$target" ] || return 1
  tmux list-clients -F '#{client_tty}' 2>/dev/null | grep -Fxq "$target"
}

run_lock_on() {
  local target="${1:-}"
  if [ -n "$target" ]; then
    TMUX_LOCK_TARGET="$target" "$ROOT_DIR/scripts/lock_on.sh"
  else
    "$ROOT_DIR/scripts/lock_on.sh"
  fi
}

run_lock_off() {
  local target="${1:-}"
  if [ -n "$target" ]; then
    TMUX_LOCK_TARGET="$target" "$ROOT_DIR/scripts/lock_off.sh"
  else
    "$ROOT_DIR/scripts/lock_off.sh"
  fi
}

disable_auto_lock() {
  local target
  if [ "$(opt @tmux_lock_auto_active)" = "on" ] && [ "$(opt @tmux_lock_state)" = "on" ]; then
    target="$(opt @tmux_lock_auto_target)"
    if ! client_exists "$target"; then
      target=""
    fi
    run_lock_off "$target" >/dev/null 2>&1 || true
  fi

  clear_auto_active
  clear_suppression
}

maybe_clear_suppression() {
  local raw="$1" pane command
  pane="$(opt @tmux_lock_auto_suppressed_pane)"
  [ -n "$pane" ] || return 0

  command="$(pane_command "$pane")"
  if ! command_matches "$command" "$raw"; then
    clear_suppression
  fi
}

mark_suppressed_if_running() {
  local pane="$1" command="$2" raw="$3"
  if command_matches "$command" "$raw"; then
    setopt @tmux_lock_auto_suppressed_pane "$pane"
    setopt @tmux_lock_auto_suppressed_command "$command"
  else
    clear_suppression
  fi
}

is_suppressed() {
  local pane="$1" raw="$2" suppressed_pane command
  suppressed_pane="$(opt @tmux_lock_auto_suppressed_pane)"
  [ -n "$suppressed_pane" ] || return 1
  [ "$pane" = "$suppressed_pane" ] || return 1

  command="$(pane_command "$pane")"
  command_matches "$command" "$raw"
}

check_active_lock() {
  local raw="$1" pane target command state
  [ "$(opt @tmux_lock_auto_active)" = "on" ] || return 1

  pane="$(opt @tmux_lock_auto_pane)"
  target="$(opt @tmux_lock_auto_target)"
  command="$(pane_command "$pane")"
  state="$(opt @tmux_lock_state)"

  if [ "$state" != "on" ]; then
    mark_suppressed_if_running "$pane" "$command" "$raw"
    clear_auto_active
    return 0
  fi

  if command_matches "$command" "$raw"; then
    return 0
  fi

  if ! client_exists "$target"; then
    target=""
  fi

  run_lock_off "$target" >/dev/null 2>&1 || true
  clear_auto_active
  clear_suppression
  return 0
}

scan_clients() {
  local raw="$1" line target pane command

  [ "$(opt @tmux_lock_state)" != "on" ] || return 0

  while IFS=$'\t' read -r target pane command; do
    [ -n "${target:-}" ] || continue
    [ -n "${pane:-}" ] || continue

    if command_matches "$command" "$raw"; then
      if is_suppressed "$pane" "$raw"; then
        continue
      fi

      if run_lock_on "$target" >/dev/null 2>&1; then
        setopt @tmux_lock_auto_active on
        setopt @tmux_lock_auto_pane "$pane"
        setopt @tmux_lock_auto_target "$target"
        setopt @tmux_lock_auto_command "$command"
        clear_suppression
      fi

      return 0
    fi
  done < <(tmux list-clients -F '#{client_tty}	#{pane_id}	#{pane_current_command}' 2>/dev/null || true)
}

check_once() {
  local raw
  raw="$(opt @tmux_lock_auto_commands)"

  if ! has_commands "$raw"; then
    disable_auto_lock
    return 0
  fi

  maybe_clear_suppression "$raw"
  check_active_lock "$raw" && return 0
  scan_clients "$raw"
}

start_monitor() {
  local raw
  raw="$(opt @tmux_lock_auto_commands)"
  if ! has_commands "$raw"; then
    setopt @tmux_lock_auto_monitor_pid ""
    return 0
  fi

  if pid_is_running; then
    return 0
  fi

  "$0" monitor >/dev/null 2>&1 &
  setopt @tmux_lock_auto_monitor_pid "$!"
}

stop_monitor() {
  local pid
  pid="$(opt @tmux_lock_auto_monitor_pid)"
  if [[ "$pid" =~ ^[0-9]+$ ]] && [ "$pid" != "$$" ]; then
    kill "$pid" 2>/dev/null || true
  fi
  setopt @tmux_lock_auto_monitor_pid ""
}

monitor_loop() {
  trap clear_monitor_pid EXIT
  setopt @tmux_lock_auto_monitor_pid "$$"

  while tmux display-message -p '#{pid}' >/dev/null 2>&1; do
    check_once || true
    sleep "$(auto_interval)"
  done
}

case "${1:-check}" in
  check)
    check_once
    ;;
  start)
    start_monitor
    ;;
  stop)
    stop_monitor
    disable_auto_lock
    ;;
  monitor)
    monitor_loop
    ;;
  *)
    echo "usage: $0 [check|start|stop|monitor]" >&2
    exit 2
    ;;
esac
