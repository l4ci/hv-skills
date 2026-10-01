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
