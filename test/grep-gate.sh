#!/usr/bin/env bash
# Final cutover gate for A9 (#53, S7). Run after bin/ is deleted, as the last
# check before the S7 PR leaves draft. Not part of smoke: it reads the tree,
# not a verb.
#
#   1. bin/ holds exactly the launcher.
#   2. No tracked file names a legacy helper, the .hv/bin mirror or hvlib.
#   3. Nothing outside history and migration code uses the old name hv-skills,
#      or the old binary name hv (#236).
#   4. `rota init` in an empty git repo works and `rota init check` exits 0.
#
# The legacy names come from test/validate-skills.py (LEGACY_HELPERS, frozen
# from bin/), the same list the doclint section uses, so there is one list.
# Usage: bash test/grep-gate.sh   (ROTA_BIN overrides the binary it builds)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
fails=0
bad() { printf '\033[31mFAIL\033[0m %s\n' "$1" >&2; fails=$((fails + 1)); }

# 1. Legacy names. The scope is what users and contributors read or run:
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
  'rota-*/' 'references/' 'docs/' 'test/' '*.md'
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

# 2. The old product name (#231). hv-skills became hv; what may still say
# hv-skills is history (CHANGELOG, the 5.0 design docs, tracked .hv/ state),
# code that has to know the old name (the migrate v4 codemod, plugin
# detection, legacy-format fixtures) and text captured from real panes. The
# managed block markers keep the key "skills" (hv-skills-start/-end), the 4.x
# plugin is "hv-skills@<marketplace>" and hv-skills-index is a legacy helper,
# so the pattern lets those through. README.md, docs/install.md and
# docs/getting-started.md belong to F5 slice B, which rewrites them after the
# rename; drop their exclusions once it merges.
OLD_NAME='(?<!@)hv-skills(?!-(?:start|end|index)\b|@)'
OLD_SCOPE=(
  ':(exclude)CHANGELOG.md'
  ':(exclude)docs/design/'
  ':(exclude).hv/'
  ':(exclude)test/grep-gate.sh'
  ':(exclude)README.md'
  ':(exclude)docs/install.md'
  ':(exclude)docs/getting-started.md'
  ':(exclude)internal/migrate/'
  ':(exclude)internal/cli/migrate_test.go'
  ':(exclude)internal/cli/testdata/golden/TestMigrateV4*'
  ':(exclude)test/sections/39_migrate.sh'
  # Legacy-format fixtures: a pre-rename block heading or .gitignore header,
  # the 4.x plugin's cache directory, and doclint not flagging the old name.
  ':(exclude)internal/knowledge/knowledge_test.go'
  ':(exclude)internal/initproj/init_test.go'
  ':(exclude)internal/skills/skills_test.go'
  ':(exclude)test/sections/04_skills.sh'
  ':(exclude)test/sections/29_doclint.sh'
  # Scrollback captured from real panes, where the checkout path shows.
  ':(exclude)internal/host/testdata/'
  ':(exclude)internal/worker/testdata/'
)
HITS="$(git grep -inIP "$OLD_NAME" -- . "${OLD_SCOPE[@]}" || true)"
if [ -n "$HITS" ]; then
  bad "the old product name hv-skills is still used ($(wc -l <<<"$HITS" | tr -d ' ') lines):"
  printf '%s\n' "$HITS" >&2
fi

# 2b. The old binary name (#236). hv became rota: skills /rota-*, state .rota/,
# env ROTA_*, markers <!-- rota:... --> and rota-<key> blocks, module
# github.com/l4ci/rota. What may still say hv: history, this repo's own state
# and instructions until the migration dogfoods them, the legacy read side
# (old markers, blocks and stamps are read until a project is migrated), the
# migrate v4 codemod, the legacy-name guards, and the files kit's and lea's
# slices of #236 rewrite next (front-door docs; release, install and update).
# Drop those slices' exclusions once they merge.
SKILLS='brainstorm|capture|debug|decide|learn|orchestrate|pause|plan|qa|refactor|release|review|ship|spike|vision|work'
HV_NAME="(?<![\\w.-])hv-(?:${SKILLS})(?![\\w-])|\\.hv/(?!bin\\b)|\\bHV_[A-Z]|\\bHV-(?:DONE|BLOCKED)\\b"
HV_NAME+="|(?:<|\\\\u003c)!-- hv[:-]|github\\.com/l4ci/hv\\b|\`hv[ \`]|\"hv\"|\\bhv\\.version\\b"
HV_SCOPE=(
  ':(exclude)CHANGELOG.md'
  ':(exclude)docs/design/5.0-helper-triage.md'
  ':(exclude)docs/design/5.0-smoke-whitebox.md'
  ':(exclude).hv/'
  ':(exclude)AGENTS.md'
  ':(exclude)CLAUDE.md'
  ':(exclude).gitignore'
  ':(exclude)test/grep-gate.sh'
  # Legacy read side and stamp migration, with their tests and fixtures.
  ':(exclude)internal/marker/'
  ':(exclude)internal/section/'
  ':(exclude)internal/round/move.go'
  ':(exclude)internal/round/move_test.go'
  ':(exclude)internal/config/fill.go'
  ':(exclude)internal/config/fill_test.go'
  ':(exclude)internal/config/schema.go'
  ':(exclude)internal/backlog/legacy_marker_test.go'
  ':(exclude)internal/backlog/issue_write_python_test.go'
  ':(exclude)internal/cli/glossary_test.go'
  ':(exclude)internal/cli/testdata/golden/TestInstructionsInitMatchGolden__*'
  ':(exclude)test/sections/02_knowledge.sh'
  ':(exclude)test/sections/13_helpers.sh'
  ':(exclude)test/sections/66_agents_md.sh'
  ':(exclude)internal/migrate/'
  # Legacy-name guards: they spell the old names to catch them.
  ':(exclude)test/validate-skills.py'
  ':(exclude)test/whitebox-scan.awk'
  ':(exclude)test/sections/29_doclint.sh'
  ':(exclude)test/sections/72_whitebox_guard.sh'
  # lea's slice: update keeps HV_* and the hv URLs until it is renamed.
  ':(exclude)VERSION'
  ':(exclude).goreleaser.yaml'
  ':(exclude).github/'
  ':(exclude)install.sh'
  ':(exclude)internal/update/'
  ':(exclude)test/sections/97_install_sh.sh'
  ':(exclude)test/sections/10_update.sh'
  ':(exclude)cmd/rota/scenarios_a4c_test.go'
  ':(exclude)cmd/rota/testdata/frozen/a4c.jsonl'
  ':(exclude)docs/design/5.0-verb-contract.md'
  # kit's slice: the front-door docs.
  ':(exclude)README.md'
  ':(exclude)docs/README.md'
  ':(exclude)docs/install.md'
  ':(exclude)docs/getting-started.md'
  ':(exclude)docs/how-it-works.md'
  ':(exclude)docs/cheatsheet.md'
  ':(exclude)docs/faq.md'
  ':(exclude)docs/walkthroughs/'
)
HITS="$(git grep -nIP "$HV_NAME" -- . "${HV_SCOPE[@]}" || true)"
if [ -n "$HITS" ]; then
  bad "the old binary name hv is still used ($(wc -l <<<"$HITS" | tr -d ' ') lines):"
  printf '%s\n' "$HITS" >&2
fi

# 3. A fresh project initializes and passes its own check.
SCRATCH="$(mktemp -d)"
trap 'rm -rf "${SCRATCH:?}"' EXIT
if [ -z "${ROTA_BIN:-}" ]; then
  VERSION="$(tr -d '[:space:]' < VERSION)"
  go build -ldflags "-X github.com/l4ci/rota/internal/version.Version=$VERSION" -o "$SCRATCH/rota" ./cmd/rota
  ROTA_BIN="$SCRATCH/rota"
fi
mkdir "$SCRATCH/proj"
git -C "$SCRATCH/proj" init -q
if (cd "$SCRATCH/proj" && "$ROTA_BIN" init >/dev/null); then
  (cd "$SCRATCH/proj" && "$ROTA_BIN" init check >/dev/null) || bad "rota init check exits non-zero in a freshly initialized repo"
else
  bad "rota init failed in an empty git repo"
fi

[ "$fails" = 0 ] || { printf '%s check(s) failed\n' "$fails" >&2; exit 1; }
printf '\033[32mgrep gate passed.\033[0m\n'
