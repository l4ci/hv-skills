# shellcheck shell=bash
# Sourceable library: the tmux host for /hv-work worker dispatch. Defines the
# hv_host_* primitives that hv-worker-dispatch, hv-worker-poll and
# hv-worker-session call; bin/hv-host-herdr.sh defines the same names for herdr.
# hv-host-select.sh sources exactly one of the two from work.dispatch.
#
# Pure library — sourcing it defines functions and runs nothing (see the
# *-preamble.sh vs *-locate.sh naming convention: only *-preamble.sh
# auto-invokes). Callers source it after hv-preamble.sh.
#
# A tmux slot's handle is its window target, `<session>:<slot>`. It is stable
# across dispatches: the window is killed and recreated under the same name.
#
# The paste path has three separate traps in it, which is why it lives here
# once rather than in each caller:
#
#   1. A long prompt sent via `send-keys` arrives as a bracketed paste that
#      swallows its own trailing Enter, and multi-line text needs quoting
#      gymnastics. load-buffer/paste-buffer sidesteps both.
#   2. Enter must be a SEPARATE keypress, and even then a pasted prompt can
#      land as a collapsed paste chip that the first Enter does not submit.
#   3. Pickup must be CONFIRMED by re-reading the pane. Assuming the first
#      Enter landed is how a dispatch goes silently missing.
#
# Captures use -J so wrapped lines are joined; without it a pane comparison is
# against hard-wrapped text and long lines read as changed when they are not.

HV_HOST=tmux

# hv_host_require — fail fast when the backend's binary is missing.
hv_host_require() {
  command -v tmux >/dev/null 2>&1 || { echo "error: tmux is not installed" >&2; return 3; }
}

# hv_host_in_session — 0 when this process runs inside a tmux pane.
# $TMUX is the only reliable signal: `tmux has-session` answers whether a
# session EXISTS, which is a different question from whether WE are in it.
hv_host_in_session() {
  [ -n "${TMUX:-}" ]
}

# hv_host_where — the name of the session we are in, for status lines.
hv_host_where() {
  tmux display-message -p '#{session_name}' 2>/dev/null || echo "?"
}

# hv_tmux_wait_ready <window> <timeout-seconds>
# Block until the pane looks like a booted Claude Code UI. Returns 1 on timeout.
# Pasting into a shell that has not yet handed off to Claude Code loses the
# text silently, which is the failure this exists to prevent.
hv_tmux_wait_ready() {
  local window="$1" timeout="$2" waited=0 pane
  while [ "$waited" -lt "$timeout" ]; do
    pane="$(tmux capture-pane -pJ -t "$window" 2>/dev/null || true)"
    case "$pane" in
      *"?"*"for shortcuts"*|*"Welcome to Claude Code"*|*"╭─"*) return 0 ;;
    esac
    sleep 2
    waited=$((waited + 2))
  done
  return 1
}

# hv_tmux_send_file <window> <file> [buffer-name]
# Paste the file's contents, submit, and confirm the pane changed. Returns 1 if
# the text never submitted after 4 attempts.
hv_tmux_send_file() {
  local window="$1" file="$2" buf="${3:-hv-send}" before after tries=0
  before="$(tmux capture-pane -pJ -t "$window" 2>/dev/null || true)"

  tmux load-buffer -b "$buf" "$file" || return 1
  tmux paste-buffer -b "$buf" -t "$window" || return 1
  tmux delete-buffer -b "$buf" 2>/dev/null || true

  while [ "$tries" -lt 4 ]; do
    sleep 1
    tmux send-keys -t "$window" C-m
    sleep 2
    after="$(tmux capture-pane -pJ -t "$window" 2>/dev/null || true)"
    [ "$after" != "$before" ] && return 0
    tries=$((tries + 1))
  done
  return 1
}

# hv_host_spawn <slot> <session> <cwd> <config-dir> <launch-cmd> <boot-timeout>
# Create the slot's window, launch Claude Code in it, wait for the UI. Prints
# the handle. Returns 3 on failure.
hv_host_spawn() {
  local slot="$1" session="$2" cwd="$3" config_dir="$4" launch="$5" timeout="$6"
  local handle="$session:$slot"
  [ -n "$config_dir" ] && launch="CLAUDE_CONFIG_DIR=$config_dir $launch"

  tmux has-session -t "$session" 2>/dev/null || tmux new-session -d -s "$session" -c "$cwd"
  tmux new-window -d -t "$session" -n "$slot" -c "$cwd" || {
    echo "error: could not create tmux window $handle" >&2; return 3; }
  tmux send-keys -t "$handle" "$launch" C-m
  hv_tmux_wait_ready "$handle" "$timeout" || {
    echo "error: slot '$slot' session did not come up within ${timeout}s" >&2; return 3; }
  printf '%s\n' "$handle"
}

# hv_host_send <slot> <handle> <file>
# Submit the file as a prompt and confirm pickup. Returns 4 if it never
# submitted. (Return 5, a dialog blocking input, is herdr-only.)
hv_host_send() {
  hv_tmux_send_file "$2" "$3" "hv-$1" || return 4
}

# hv_host_capture <slot> <handle> <lines> — print the pane text.
# An empty target would capture the CALLER's pane, so a slot with no handle
# yields nothing.
hv_host_capture() {
  [ -n "$2" ] || return 0
  tmux capture-pane -pJ -t "$2" 2>/dev/null || true
}

# hv_host_status <slot> <handle> — tmux has no native agent state; print
# nothing so the classifier decides from pane text and movement alone.
hv_host_status() {
  :
}

# _hv_tmux_window_pid <session:window> — the pane PID of the window with that
# exact name, empty when there is none. Exact match: a bare `-t` target would
# also take a prefix, so `w1` could be answered by `w10`.
_hv_tmux_window_pid() {
  tmux list-windows -t "${1%%:*}" -F '#{window_name} #{pane_pid}' 2>/dev/null \
    | awk -v n="${1#*:}" '$1 == n { print $2; exit }'
}

# hv_host_kill <slot> <handle> — destroy the slot's window and prove it is
# gone. Records the window's pane PID first; returns 1 (with a message) unless
# the window no longer exists and that PID has exited. A swallowed failure here
# would leave the old session running beside the next one in the same worktree.
hv_host_kill() {
  [ -n "$2" ] || return 0
  local pid="" i=0
  pid="$(_hv_tmux_window_pid "$2")"
  tmux kill-window -t "$2" 2>/dev/null || true
  while :; do
    if [ -z "$(_hv_tmux_window_pid "$2")" ] && { [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; }; then
      return 0
    fi
    i=$((i + 1))
    [ "$i" -lt "${HV_HOST_KILL_WAIT:-10}" ] || break
    sleep 1
  done
  echo "error: slot '$1' previous session is still running (window $2${pid:+, pid $pid}); not spawning a second one" >&2
  return 1
}

# hv_host_notify <title> <body> — tmux has no notification surface.
hv_host_notify() {
  :
}
