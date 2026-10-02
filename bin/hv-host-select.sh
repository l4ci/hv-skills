# shellcheck shell=bash
# Sourceable library: pick the /hv-work worker host from work.dispatch and
# source its primitives (bin/hv-host-tmux.sh or bin/hv-host-herdr.sh).
#
# Pure library — sourcing it defines hv_host_select and runs nothing (see the
# *-preamble.sh vs *-locate.sh naming convention). Callers source it after
# hv-preamble.sh, then call hv_host_select once.
#
# "herdr" selects the herdr host. Anything else, including the default
# "subagent", selects tmux: the worker helpers predate work.dispatch=herdr and
# have always driven tmux when called directly.

# hv_host_select — source the host lib for work.dispatch; sets HV_HOST.
hv_host_select() {
  local dispatch
  dispatch="$(PYTHONPATH="$HERE${PYTHONPATH:+:$PYTHONPATH}" python3 -c \
    'from hvlib import load_config; print((load_config().get("work", {}) or {}).get("dispatch") or "")')"
  case "$dispatch" in
    herdr) . "$HERE/hv-host-herdr.sh" ;;
    *)     . "$HERE/hv-host-tmux.sh" ;;
  esac
}

# hv_pid_alive <pid> — 0 while the process exists and has not exited. A zombie
# has exited and only waits for its parent to reap it, so `kill -0` alone would
# call it alive and a slow reaper would read as a session that will not close.
hv_pid_alive() {
  kill -0 "$1" 2>/dev/null || return 1
  case "$(ps -o stat= -p "$1" 2>/dev/null | tr -d ' ')" in Z*|"") return 1 ;; esac
  return 0
}

# hv_pid_tree <pid> — the pid and all its descendants, space-separated. Taken
# BEFORE a close: afterwards orphaned children are reparented and unfindable.
hv_pid_tree() {
  ps -A -o pid= -o ppid= 2>/dev/null | awk -v root="$1" '
    { kids[$2] = kids[$2] " " $1 }
    END {
      n = split(root, q, " "); out = root
      for (i = 1; i <= n; i++) {
        m = split(kids[q[i]], c, " ")
        for (j = 1; j <= m; j++) { q[++n] = c[j]; out = out " " c[j] }
      }
      print out
    }'
}
