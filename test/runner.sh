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

# Pin hv-resolve-plugin-root to the canonical repo bin/ during smoke. Without
# this, hv-preflight walks ~/.claude/plugins/* and may pick up a stale
# marketplace install with helpers that have since been removed (false-positive
# "stale: missing helpers"). The smoke is about *this* checkout, not whatever
# Claude Code happens to have installed locally.
export HV_INSTALL_ROOT="$REPO"
# macOS mktemp returns /var/folders/... but the underlying dir is /private/var/folders/... .
# Resolve to the physical path here so sections comparing against $TMP match `pwd -P` output
# from helpers like hv-resolve-umbrella (which would otherwise mismatch on Darwin).
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

# Leak guard: snapshot $REPO/CLAUDE.md and the dev tree's tracked .hv/
# content before any section runs. Under v4.1's partial-tracking model
# (.hv/ files committed to the repo), a section helper that walks up past
# $TMP can clobber real project state. The post-loop assertion below
# restores + fails. The check is explicit-at-end (not EXIT-trap-based)
# because sections follow the F38 local-trap convention and overwrite
# EXIT — see test/lib.sh.
REPO_CLAUDE="$REPO/CLAUDE.md"
REPO_CLAUDE_SNAP=""
if [ -f "$REPO_CLAUDE" ]; then
  REPO_CLAUDE_SNAP="$(mktemp)"
  cp "$REPO_CLAUDE" "$REPO_CLAUDE_SNAP"
fi
# Snapshot dev tree's tracked .hv/ content. We snap the whole subtree
# (excluding gitignored paths) so any leak surfaces as a diff at the end.
REPO_HV_SNAP=""
if [ -d "$REPO/.hv" ]; then
  REPO_HV_SNAP="$(mktemp -d)"
  # Use git ls-files to capture exactly what git tracks, preserving paths.
  (cd "$REPO" && git ls-files .hv/) | while IFS= read -r f; do
    mkdir -p "$REPO_HV_SNAP/$(dirname "$f")"
    cp "$REPO/$f" "$REPO_HV_SNAP/$f"
  done
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
#
# cd back to $TMP before each section. Under v4.1's partial-tracking model,
# a section that leaves cwd inside a sub-fixture (via inner cd) and lets the
# next section's `.hv/` writes target the dev tree's `.hv/` is a real leak.
# This pin is defensive — sections following the F38 local-trap convention
# should already restore cwd, but enforcing it at the boundary makes the
# leak guard catch only true walk-up clobbers, not cwd-drift residue.
for f in "$TESTDIR/sections/"*.sh; do
  [ -f "$f" ] || continue
  cd "$TMP"
  source "$f"
done

# Leak guard assertion: if any section wrote to $REPO/CLAUDE.md or any
# tracked .hv/ file in the dev tree, restore from snapshot and fail.
# Smoke is supposed to be hermetic w.r.t. $TMP; a diff here means a
# helper walked up past $TMP/.hv to the dev tree's.
LEAKED=0
if [ -n "$REPO_CLAUDE_SNAP" ] && ! cmp -s "$REPO_CLAUDE_SNAP" "$REPO_CLAUDE"; then
  printf '\n\033[31merror: smoke leaked into %s — restoring from snapshot\033[0m\n' "$REPO_CLAUDE" >&2
  cp "$REPO_CLAUDE_SNAP" "$REPO_CLAUDE"
  LEAKED=1
fi
if [ -n "$REPO_HV_SNAP" ]; then
  while IFS= read -r f; do
    snap_path="$REPO_HV_SNAP/$f"
    live_path="$REPO/$f"
    if [ -f "$snap_path" ] && [ -f "$live_path" ] && ! cmp -s "$snap_path" "$live_path"; then
      printf '\n\033[31merror: smoke leaked into %s — restoring from snapshot\033[0m\n' "$live_path" >&2
      cp "$snap_path" "$live_path"
      LEAKED=1
    elif [ -f "$snap_path" ] && [ ! -f "$live_path" ]; then
      printf '\n\033[31merror: smoke deleted %s — restoring from snapshot\033[0m\n' "$live_path" >&2
      mkdir -p "$(dirname "$live_path")"
      cp "$snap_path" "$live_path"
      LEAKED=1
    fi
  done < <(cd "$REPO_HV_SNAP" && find . -type f | sed 's|^\./||')
fi
[ -n "$REPO_CLAUDE_SNAP" ] && rm -f "$REPO_CLAUDE_SNAP"
[ -n "$REPO_HV_SNAP" ] && rm -rf "$REPO_HV_SNAP"
[ "$LEAKED" = 1 ] && exit 1

printf '\n\033[32mAll smoke tests passed.\033[0m\n'
