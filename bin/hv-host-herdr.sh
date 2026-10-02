# shellcheck shell=bash
# Sourceable library: the herdr host for /hv-work worker dispatch. Defines the
# same hv_host_* primitives as bin/hv-host-tmux.sh, backed by the herdr CLI.
# hv-host-select.sh sources exactly one of the two from work.dispatch.
#
# Pure library — sourcing it defines functions and runs nothing (see the
# *-preamble.sh vs *-locate.sh naming convention: only *-preamble.sh
# auto-invokes). Callers source it after hv-preamble.sh.
#
# A herdr slot is a TAB in the current workspace whose root pane runs Claude
# Code in the slot's hv-managed worktree. The handle is the tab id (`w1:t7`).
# Tab ids are never reused, so the handle changes on every dispatch and the
# caller must persist it. The agent's name is derived from slot + handle
# (`hv-w1-w1-t7`): herdr agent names are unique per SERVER, and a bare `w1`
# would collide with another repo's pool on the same server.
#
# Every herdr command prints JSON on stdout and, on failure, a JSON error on
# stderr with exit 1. herdr reports agent state natively (idle, working,
# blocked, done, unknown), so this host needs none of tmux's paste tricks:
# `agent prompt` submits text and Enter as one ordered write.

HV_HOST=herdr

# _hv_herdr_get <dotted.key.path> — read one herdr JSON reply from stdin and
# print the value at that path (empty on a missing key or bad JSON).
_hv_herdr_get() {
  python3 -c '
import json, sys
try:
    v = json.load(sys.stdin)
    for k in sys.argv[1].split("."):
        v = v[k]
except Exception:
    v = ""
print("" if v is None else v)
' "$1"
}

# _hv_herdr_errcode <stderr-file> — the `.error.code` of a herdr failure.
_hv_herdr_errcode() {
  _hv_herdr_get error.code <"$1"
}

# hv_herdr_agent_name <slot> <handle> — the agent name this slot runs under.
hv_herdr_agent_name() {
  printf 'hv-%s-%s\n' "$1" "$(printf '%s' "$2" | tr ':' '-')"
}

hv_host_require() {
  command -v herdr >/dev/null 2>&1 || { echo "error: herdr is not installed" >&2; return 3; }
}

# hv_host_in_session — 0 when this process runs in a herdr-managed pane.
# herdr injects HERDR_ENV=1 into every pane it manages. Controlling a herdr
# server from outside one is what herdr's own guide forbids: commands then
# land in whatever workspace a human happens to have focused.
hv_host_in_session() {
  [ "${HERDR_ENV:-}" = 1 ] && [ -n "${HERDR_WORKSPACE_ID:-}" ]
}

hv_host_where() {
  printf 'herdr workspace %s\n' "${HERDR_WORKSPACE_ID:-?}"
}

# hv_herdr_launch_args <launch-cmd>
# Split a worker launch command for `herdr agent start --kind claude`, which
# runs the claude binary itself and takes only its arguments. Prints one line
# per token: `env KEY=VALUE` for leading assignments (passed to the tab as
# --env), then `arg <token>` for every argument after the binary. Exits 1
# when the command does not launch claude, since agent start cannot run it.
hv_herdr_launch_args() {
  python3 - "$1" <<'PY'
import os, re, shlex, sys
toks = shlex.split(sys.argv[1])
i = 0
while i < len(toks) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", toks[i]):
    print("env " + toks[i]); i += 1
if i >= len(toks) or os.path.basename(toks[i]) != "claude":
    raise SystemExit(1)
for t in toks[i + 1:]:
    print("arg " + t)
PY
}

# hv_herdr_dialog_keys <pane-text-file>
# Claude Code can open on a startup dialog: the folder-trust prompt for a
# fresh worktree, or the Bypass Permissions warning on a config dir that has
# not accepted it yet. The two put their accepting option in different
# positions, so a fixed keypress picks "No, exit" on one of them. Read the
# numbered options, find the accepting one and the cursor (❯), and print the
# keys that move between them plus `enter`. Exits 1 on an unknown dialog.
hv_herdr_dialog_keys() {
  python3 - "$1" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
ACCEPT = ("Yes, I trust this folder", "Yes, I accept", "Yes, proceed")
cursor = target = None
for line in text.splitlines():
    m = re.match(r"^\s*(❯|>)?\s*(\d+)\.\s+(.*\S)", line)
    if not m:
        continue
    n = int(m.group(2))
    if m.group(1):
        cursor = n
    if target is None and any(a in m.group(3) for a in ACCEPT):
        target = n
if target is None:
    raise SystemExit(1)
cursor = cursor or 1
step = "down" if target >= cursor else "up"
print(" ".join([step] * abs(target - cursor) + ["enter"]))
PY
}

# hv_host_spawn <slot> <session> <cwd> <config-dir> <launch-cmd> <boot-timeout>
# Adopt the worktree as a new background tab, start Claude Code in it, clear
# any startup dialog, and wait for it to idle. Prints the tab id (the handle).
# <session> is unused: herdr tabs live in the caller's own workspace.
hv_host_spawn() {
  local slot="$1" cwd="$3" config_dir="$4" launch="$5" timeout="$6"
  local err out tab pane name kind val code keys i=0 status
  # ${arr[@]+"${arr[@]}"} below: bash 3.2 (macOS) treats an empty array as
  # unbound under set -u.
  local -a tab_args=() agent_args=()
  err="$(mktemp)"

  out="$(hv_herdr_launch_args "$launch")" || {
    echo "error: work.dispatch=herdr launches claude itself; workerCommand must run claude, got: $launch" >&2
    rm -f "$err"; return 3; }
  while IFS=' ' read -r kind val; do
    case "$kind" in
      env) tab_args+=(--env "$val") ;;
      arg) agent_args+=("$val") ;;
    esac
  done <<EOF
$out
EOF
  # Account selection must happen at tab creation: agent start runs the
  # binary directly and ignores shell aliases or wrappers.
  [ -n "$config_dir" ] && tab_args+=(--env "CLAUDE_CONFIG_DIR=$config_dir")

  out="$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$cwd" \
           --label "$slot" --no-focus ${tab_args[@]+"${tab_args[@]}"} 2>"$err")" || {
    echo "error: herdr tab create failed for slot '$slot': $(cat "$err")" >&2
    rm -f "$err"; return 3; }
  tab="$(printf '%s' "$out" | _hv_herdr_get result.tab.tab_id)"
  pane="$(printf '%s' "$out" | _hv_herdr_get result.root_pane.pane_id)"
  [ -n "$tab" ] && [ -n "$pane" ] || {
    echo "error: herdr tab create returned no tab/pane id for slot '$slot'" >&2
    rm -f "$err"; return 3; }

  name="$(hv_herdr_agent_name "$slot" "$tab")"
  if ! herdr agent start "$name" --kind claude --pane "$pane" \
        --timeout "$((timeout * 1000))" -- ${agent_args[@]+"${agent_args[@]}"} >/dev/null 2>"$err"; then
    code="$(_hv_herdr_errcode "$err")"
    [ "$code" = "agent_not_ready" ] || {
      echo "error: herdr agent start failed for slot '$slot' ($tab): $(cat "$err")" >&2
      rm -f "$err"; return 3; }
    # Blocked at startup: answer up to two dialogs (trust, then bypass).
    while :; do
      herdr agent read "$name" --source visible 2>/dev/null \
        | _hv_herdr_get result.read.text >"$err.pane"
      keys="$(hv_herdr_dialog_keys "$err.pane")" || {
        echo "error: slot '$slot' is stuck on an unrecognised startup dialog in tab $tab" >&2
        rm -f "$err" "$err.pane"; return 3; }
      # shellcheck disable=SC2086 # keys is a space-separated key list
      herdr agent send-keys "$name" $keys >/dev/null 2>&1 || true
      out="$(herdr agent wait "$name" --until idle --until blocked \
               --timeout "$((timeout * 1000))" 2>/dev/null || true)"
      status="$(printf '%s' "$out" | _hv_herdr_get result.agent.agent_status)"
      [ "$status" = "idle" ] && break
      i=$((i + 1))
      [ "$i" -lt 3 ] || {
        echo "error: slot '$slot' did not reach idle after its startup dialogs (tab $tab)" >&2
        rm -f "$err" "$err.pane"; return 3; }
    done
  fi
  rm -f "$err" "$err.pane"
  printf '%s\n' "$tab"
}

# hv_host_send <slot> <handle> <file>
# Submit the file and confirm pickup: return once the agent is observed
# working (or blocked on a dialog), NOT when the task finishes — plain --wait
# would hold until the whole task settled. Returns 4 when no activity
# followed the submission, 5 when a dialog was already up (nothing was sent).
hv_host_send() {
  local name err code
  name="$(hv_herdr_agent_name "$1" "$2")"
  err="$(mktemp)"
  if herdr agent prompt "$name" "$(cat "$3")" --wait --until working --until blocked \
       --timeout 60000 >/dev/null 2>"$err"; then
    rm -f "$err"; return 0
  fi
  code="$(_hv_herdr_errcode "$err")"
  rm -f "$err"
  case "$code" in
    agent_blocked) return 5 ;;
    *)             return 4 ;;
  esac
}

# hv_host_capture <slot> <handle> <lines> — print recent pane text with soft
# wraps joined (the herdr twin of capture-pane -J).
hv_host_capture() {
  [ -n "$2" ] || return 0
  herdr agent read "$(hv_herdr_agent_name "$1" "$2")" --source recent-unwrapped \
    --lines "$3" 2>/dev/null | _hv_herdr_get result.read.text
}

# hv_host_status <slot> <handle> — herdr's native agent state, or `gone` when
# the slot has a tab but no agent in it (the session exited back to a shell).
# Prints nothing for a never-dispatched slot.
hv_host_status() {
  local out
  [ -n "$2" ] || return 0
  if out="$(herdr agent get "$(hv_herdr_agent_name "$1" "$2")" 2>/dev/null)"; then
    printf '%s' "$out" | _hv_herdr_get result.agent.agent_status
  else
    echo gone
  fi
}

# hv_host_kill <slot> <handle> — ask the session to exit, close its tab, and
# prove it is gone. Records the pane's process PIDs first (claude plus its MCP
# children); returns 1 (with a message) unless `tab get` fails and every
# recorded PID has exited. Closed tab ids are never reused, so a failing
# `tab get` is unambiguous. `/exit` is a client-side command, so no wait: it
# produces no turn to observe; it lets Claude Code flush its session first.
hv_host_kill() {
  [ -n "$2" ] || return 0
  local name pane pids="" pid alive="" i=0
  name="$(hv_herdr_agent_name "$1" "$2")"
  pane="$(herdr agent get "$name" 2>/dev/null | _hv_herdr_get result.agent.pane_id || true)"
  [ -z "$pane" ] || pids="$(herdr pane process-info --pane "$pane" 2>/dev/null | python3 -c '
import json, sys
try:
    info = json.load(sys.stdin)["result"]["process_info"]
    pids = [p["pid"] for p in info.get("foreground_processes", [])]
    if info.get("shell_pid"):
        pids.append(info["shell_pid"])
    print(" ".join(str(p) for p in pids))
except Exception:
    pass
' || true)"
  herdr agent prompt "$name" "/exit" >/dev/null 2>&1 || true
  herdr tab close "$2" >/dev/null 2>&1 || true
  while :; do
    alive=""
    for pid in $pids; do hv_pid_alive "$pid" && alive="$alive $pid"; done
    if ! herdr tab get "$2" >/dev/null 2>&1 && [ -z "$alive" ]; then
      return 0
    fi
    i=$((i + 1))
    [ "$i" -lt "${HV_HOST_KILL_WAIT:-10}" ] || break
    sleep 1
  done
  echo "error: slot '$1' previous session is still running (tab $2${alive:+, pids$alive}); not spawning a second one" >&2
  return 1
}

# hv_host_notify <title> <body> — raise a herdr notification with sound.
hv_host_notify() {
  herdr notification show "$1" --body "$2" --sound request >/dev/null 2>&1 || true
}
