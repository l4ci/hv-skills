# shellcheck shell=bash
# Shared helper for artifact-removal scripts (hv-design-rm, hv-plan-rm, …).
# Source after hv-preamble.sh; call hv_artifact_rm <kind> <id> <dir>.
#
# Exit codes: 0 success, 1 artifact not found.

hv_artifact_rm() {
  local kind="$1" id="$2" dir="$3"
  local path="${dir}/${id}.md"
  if [ ! -f "$path" ]; then
    echo "error: $path not found" >&2
    exit 1
  fi
  rm "$path"
}
