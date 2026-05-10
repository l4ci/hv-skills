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

cd "$TMP"
mkdir -p .hv/bugs .hv/features .hv/tasks .hv/milestones

cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
EOF
cat > .hv/MILESTONES.md <<'EOF'
# Vision

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

# Source sections in alphabetical/numeric order. The numeric prefix is the
# canonical ordering; new sections insert at the next free slot.
for f in "$TESTDIR/sections/"*.sh; do
  [ -f "$f" ] || continue
  source "$f"
done

printf '\n\033[32mAll smoke tests passed.\033[0m\n'
