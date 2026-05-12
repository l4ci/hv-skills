#!/usr/bin/env bash
# Smoke test for .hv/bin/ helpers. Builds a throwaway .hv/ in a tmpdir, then
# sources every section under test/sections/ in alphabetical order. Each
# section runs in the shared $TMP cwd and may rely on cumulative state from
# earlier sections — order is load-bearing.
# Usage: bash test/runner.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/bin"
TESTDIR="$REPO/test"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Leak guard: snapshot $REPO/CLAUDE.md before any section runs. The
# post-loop assertion below restores + fails if a section's helper walks
# up past $TMP and rewrites the dev tree's CLAUDE.md. The check is
# explicit-at-end (not EXIT-trap-based) because sections follow the
# F38 local-trap convention and overwrite EXIT — see test/lib.sh.
REPO_CLAUDE="$REPO/CLAUDE.md"
REPO_CLAUDE_SNAP=""
if [ -f "$REPO_CLAUDE" ]; then
  REPO_CLAUDE_SNAP="$(mktemp)"
  cp "$REPO_CLAUDE" "$REPO_CLAUDE_SNAP"
fi

cd "$TMP"
mkdir -p .hv/bugs .hv/features .hv/tasks .hv/milestones

cat > .hv/BACKLOG.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
EOF
cat > .hv/MILESTONES.md <<'EOF'
# Milestones

_(no vision yet — run `/hv-vision` to brainstorm milestones)_

## Active milestones

_(none active — set with `/hv-vision`)_

## Milestones
EOF
echo '{"bugs":0,"features":0,"tasks":0,"milestones":0}' > .hv/counters.json
echo '{"active":[]}' > .hv/status.json

git init -q
git config user.email t@t && git config user.name t
git checkout -q -b main 2>/dev/null || git branch -m main
git add -A && git commit -q -m "seed"

# Source pass()/fail() so sections can use them.
source "$TESTDIR/lib.sh"

# F62 — static preamble scan: shadowing / trap-convention violations
# in test/sections/*.sh fail fast before any section runs.
check_section_conventions "$TESTDIR/sections" || exit 1

# Source sections in alphabetical/numeric order. The numeric prefix is the
# canonical ordering; new sections insert at the next free slot.
for f in "$TESTDIR/sections/"*.sh; do
  [ -f "$f" ] || continue
  source "$f"
done

# Leak guard assertion: if any section wrote to $REPO/CLAUDE.md, restore
# from snapshot and fail. Smoke is supposed to be hermetic w.r.t. $TMP;
# a diff here means a helper walked up past $TMP/.hv to the dev tree's.
if [ -n "$REPO_CLAUDE_SNAP" ] && ! cmp -s "$REPO_CLAUDE_SNAP" "$REPO_CLAUDE"; then
  printf '\n\033[31merror: smoke leaked into %s — restoring from snapshot\033[0m\n' "$REPO_CLAUDE" >&2
  cp "$REPO_CLAUDE_SNAP" "$REPO_CLAUDE"
  rm -f "$REPO_CLAUDE_SNAP"
  exit 1
fi
[ -n "$REPO_CLAUDE_SNAP" ] && rm -f "$REPO_CLAUDE_SNAP"

printf '\n\033[32mAll smoke tests passed.\033[0m\n'
