#!/usr/bin/env bash
# Final cutover gate for A9 (#53, S7). Run after bin/ is deleted, as the last
# check before the S7 PR leaves draft. Not part of smoke: it reads the tree,
# not a verb.
#
#   1. bin/ holds exactly the `hv` launcher.
#   2. No tracked file names a legacy helper, the .hv/bin mirror or hvlib.
#   3. `hv init` in an empty git repo works and `hv init check` exits 0.
#
# The legacy names come from test/validate-skills.py (LEGACY_HELPERS, frozen
# from bin/), the same list the doclint section uses, so there is one list.
# Usage: bash test/grep-gate.sh   (HV_BIN overrides the binary it builds)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
fails=0
bad() { printf '\033[31mFAIL\033[0m %s\n' "$1" >&2; fails=$((fails + 1)); }

# 1. bin/ is exactly the launcher.
BIN_LS="$(git ls-files bin | sort | tr '\n' ' ')"
[ "$BIN_LS" = "bin/hv " ] || bad "bin/ must hold only the hv launcher; tracked: $BIN_LS"

# 2. Legacy names. The scope is what users and contributors read or run:
# skills, references, docs, the root Markdown, test/ and Go tests. Non-test Go
# source under internal/ is out of scope (A9 ruling, option a): it cites the
# helper each verb was ported from, and some of it has to know the old names
# (init deleting the 4.x mirror, the migrate v4 codemod). History keeps them
# too: the 5.0 design docs cite helpers as what they
# replaced. The validator owns the name list, and the white-box scanner, its
# guard section, the doclint section and this gate spell the patterns.
NAMES="$(python3 test/validate-skills.py --list-legacy | paste -sd'|')"
[ -n "$NAMES" ] || bad "validate-skills.py --list-legacy printed no names"
PATTERN="(?<![\\w/.-])(?:${NAMES})(?![\\w-])|\\.hv/bin|hvlib|(?<![\\w.-])bin/hv-"
SCOPE=(
  'hv-*/' 'references/' 'docs/' 'test/' '*.md'
  ':(glob)**/*_test.go' ':(glob)**/testdata/**'
  ':(exclude)CHANGELOG.md'
  ':(exclude)docs/design/5.0-*'
  ':(exclude).hv'
  ':(exclude)test/grep-gate.sh'
  ':(exclude)test/validate-skills.py'
  ':(exclude)test/whitebox-scan.awk'
  ':(exclude)test/sections/29_doclint.sh'
  ':(exclude)test/sections/72_whitebox_guard.sh'
  # Tests of the code that has to know the old names: the migrate v4 codemod
  # and init removing the 4.x mirror. Their fixtures are legacy text on purpose.
  ':(exclude)test/sections/39_migrate.sh'
  ':(exclude)internal/migrate'
  ':(exclude)internal/cli/migrate_test.go'
  ':(exclude)internal/cli/testdata/golden/TestMigrateV4*'
  ':(exclude)internal/cli/init_test.go'
  ':(exclude)internal/initproj'
)
HITS="$(git grep -nP "$PATTERN" -- "${SCOPE[@]}" || true)"
if [ -n "$HITS" ]; then
  bad "legacy helper names, .hv/bin or hvlib still referenced ($(wc -l <<<"$HITS" | tr -d ' ') lines):"
  printf '%s\n' "$HITS" >&2
fi

# 3. A fresh project initializes and passes its own check.
SCRATCH="$(mktemp -d)"
trap 'rm -rf "${SCRATCH:?}"' EXIT
if [ -z "${HV_BIN:-}" ]; then
  VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' .claude-plugin/plugin.json)"
  go build -ldflags "-X github.com/l4ci/hv-skills/v5/internal/version.Version=$VERSION" -o "$SCRATCH/hv" ./cmd/hv
  HV_BIN="$SCRATCH/hv"
fi
mkdir "$SCRATCH/proj"
git -C "$SCRATCH/proj" init -q
if (cd "$SCRATCH/proj" && "$HV_BIN" init >/dev/null); then
  (cd "$SCRATCH/proj" && "$HV_BIN" init check >/dev/null) || bad "hv init check exits non-zero in a freshly initialized repo"
else
  bad "hv init failed in an empty git repo"
fi

[ "$fails" = 0 ] || { printf '%s check(s) failed\n' "$fails" >&2; exit 1; }
printf '\033[32mgrep gate passed.\033[0m\n'
