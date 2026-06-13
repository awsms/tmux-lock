# tmux-lock

A tmux plugin that gives you a passthrough/lock inspired by Zellij's **LOCK** feature.
When locked, tmux gets out of the way and your terminal app (remote SSH sesion, editor, REPL, etc.) receives raw keys.
Then unlock to get all your tmux keybindings back.

* By default, shows a **LOCKED** badge in `status-left` while active. Theme of the badge was made to be used with `fabioluciano/tmux-tokyo-night` (as that's what I use).
* You can also completely hide tmux's status bar on **LOCK** (so only the nested tmux status bar, or nvim status bar is visible for ex).
* Optionally auto-locks while configured programs are running in the active pane, then unlocks when they exit.
* Disables the tmux prefix while locked (so you don't accidentally trigger tmux commands). Thus lets you use the same prefix key for nested/remote and local tmux.
* tl;dr how it works: it saves your current root-table bindings and user-keys, wipes everything, then restores them on unlock.

---

## Install

### With TPM (recommended)

Add to your `~/.tmux.conf` **before** loading tpm:

```tmux
# load the plugin
set -g @plugin 'awsms/tmux-lock'

set -g @tmux_lock_toggle_key 'C-b'   # example: change toggle key
set -g @tmux_lock_auto_commands 'vim micro nvim'

...

run '~/.tmux/plugins/tpm/tpm'
```

Reload TPM: `prefix` + `I`.

### Manual

Clone anywhere and source the entry script:

```tmux
# load the plugin
run-shell '/path/to/tmux-lock.tmux'

set -g @tmux_lock_toggle_key 'C-b'
```

---

## Usage

* **Toggle lock:** press the toggle key (default **`C-Space`**).
* **Auto-lock:** configure commands in `@tmux_lock_auto_commands` before loading the plugin:

  ```tmux
  set -g @tmux_lock_auto_commands 'vim micro nvim'
  # this also works:
  set -g @tmux_lock_auto_commands '[ "vim", "micro", "nvim" ]'
  ```

  tmux-lock checks attached clients' active panes once per second by default. When the foreground command matches the list, it locks that client; when the command exits, it unlocks. If you manually unlock while the command is still running, auto-lock stays suppressed for that pane until the command exits.
* **Unlock:**

  * Press the **rescue key**: **`M-Escape`** (Alt+Esc)
  * or **click** the left status segment while locked.

---

## What it does (when locking)

* Saves your current `-T root` key bindings and selected `user-keys[...]`, then unbinds them.
* Turns **`xterm-keys` off** and sets **prefix to `None`** so raw CSI sequences go to the app in the current window.
* Switches your client to the **`off`** key-table for passthrough.
* Paints `status-left` with a bold **LOCKED** badge.
* Leaves a minimal escape both in `root` and `off` tables so you can always unlock.

On unlock, everything above is restored and `status-left` returns to what you had.

---

## Options

| Option                      | Default        | What it does                                                                   |
| --------------------------- | -------------- | ------------------------------------------------------------------------------ |
| `@tmux_lock_toggle_key`     | `C-Space`          | Key to toggle lock. Bound in both `root` and `off` tables.                 |
| `@tmux_lock_rescue_key`     | `M-Escape`     | Always unlock (works from any table).                                          |
| `@tmux_lock_user_keys`      | `""`           | Space-separated list of user-keys indices to preserve/restore (e.g. `"0 1 2"`).|
| `@tmux_lock_passthrough_bg` | `#f7768e`      | Background color of the LOCKED badge.                                          |
| `@tmux_lock_bar_bg`         | `#292e42`      | Status bar background next to the badge.                                       |
| `@tmux_lock_p_text_color`   | `#ffffff`      | Text color of the badge.                                                       |
| `@tmux_lock_state`          | `off`          | Initial state at startup (`on`/`off`).                                         |
| `@tmux_lock_block`          | *(auto-built)* | Format used for the LOCKED badge (you can fully override if you want).         |
| `@tmux_hide_status_onlock`  | `false`        | When `true`, hide the status bar while locked and restore it on unlock.        |
| `@tmux_lock_auto_commands`  | `""`           | Space/comma/JSON-ish list of foreground commands that should auto-lock, e.g. `vim micro nvim`. |
| `@tmux_lock_auto_interval`  | `1`            | Auto-lock monitor interval in seconds.                                         |
> Note: `@tmux_lock_unbind_keys` exists in the codebase for testing, but the plugin currently saves **all** root binds and unbinds them while locked (then restores on unlock).

---

## Tips & troubleshooting

* If you ever get confused about state, press **`M-Escape`** to force unlock.
* You can also run: `tmux run-shell '/path/to/scripts/with_lock.sh off'`.
* (currently experimental) the plugin targets the **current client** via `TMUX_LOCK_TARGET=#{client_tty}`, so locking one tmux client won't affect others.

## Testing

The test harness uses a private tmux socket under `/tmp` and unsets any inherited `TMUX`, so local runs do not touch your real tmux server:

```bash
tests/test_tmux_lock.sh
```

For the container suite, run without allocating a TTY:

```bash
podman run --rm --network none --security-opt no-new-privileges --pids-limit 256 tmux-lock-test
```

---

## Credits

Huge thanks to [Alexey Samoshkin](https://scribe.rip/@alexeysamoshkin/tmux-in-practice-local-and-nested-remote-tmux-sessions-4f7ba5db8795), as I was struggling to get this zellij feature back to tmux.
