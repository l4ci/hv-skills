# shellcheck shell=bash
# Sourceable library: put text into a tmux window running a Claude Code session
# and confirm it was actually submitted.
#
# Pure library — sourcing it defines functions and runs nothing (see the
# *-preamble.sh vs *-locate.sh naming convention: only *-preamble.sh
# auto-invokes). Callers source it after hv-preamble.sh.
#
# Shared by hv-worker-dispatch (task briefs, relayed answers) and
# hv-worker-session (the operator handoff). The paste path has three separate
# traps in it and duplicating them across two callers guarantees they drift:
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
