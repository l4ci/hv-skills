# shellcheck shell=bash
# Shared helper for artifact-amend scripts (hv-design-amend, …).
# Source after hv-preamble.sh; call:
#   hv_artifact_amend <kind> <id> <dir> <section> <mode> <text>
# <mode> is "append" or "replace". Amends the `## <section>` body of
# <dir>/<id>.md in place (atomic write).
#
# Exit codes: 0 success, 1 artifact not found / section not found / bad mode.

hv_artifact_amend() {
  local kind="$1" id="$2" dir="$3" section="$4" mode="$5" text="$6"
  local path="${dir}/${id}.md"
  if [ ! -f "$path" ]; then
    echo "error: $path not found" >&2
    exit 1
  fi
  if [ "$mode" != "append" ] && [ "$mode" != "replace" ]; then
    echo "error: mode must be 'append' or 'replace', got '$mode'" >&2
    exit 1
  fi
  export _HV_AA_PATH="$path"
  export _HV_AA_SECTION="$section"
  export _HV_AA_MODE="$mode"
  export _HV_AA_TEXT="$text"
  PYTHONPATH="$HERE${PYTHONPATH:+:$PYTHONPATH}" python3 - <<'PY'
import os
import sys
from hvlib import read_or_empty, write_text_atomic, find_section, replace_section, append_to_section

path = os.environ["_HV_AA_PATH"]
section = os.environ["_HV_AA_SECTION"]
mode = os.environ["_HV_AA_MODE"]
text = os.environ.get("_HV_AA_TEXT", "")

content = read_or_empty(path)
if find_section(content, section) is None:
    print(f"error: section '## {section}' not found in {path}", file=sys.stderr)
    sys.exit(1)

if mode == "replace":
    new = replace_section(content, section, "\n" + text.rstrip("\n") + "\n\n")
else:
    new = append_to_section(content, section, "\n" + text.rstrip("\n") + "\n\n")

write_text_atomic(path, new)
PY
}
