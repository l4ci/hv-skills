# shellcheck shell=bash
# Shared helper for artifact-show scripts (hv-design-show, hv-plan-show, …).
# Future consumers: hv-vision-show, hv-spike-show (added in F26 sibling tasks).
# Source after hv-preamble.sh; call hv_artifact_show <kind> <id> <dir>.
#
# Exit codes: 0 success, 1 artifact not found.

hv_artifact_show() {
  local kind="$1" id="$2" dir="$3"
  local path="${dir}/${id}.md"
  if [ ! -f "$path" ]; then
    echo "error: $path not found" >&2
    exit 1
  fi
  cat "$path"
}
