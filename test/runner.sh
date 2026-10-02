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
# Root every temp dir of this run under one base (#110). Sections, the shim and
# the helpers all call mktemp, and sections replace the EXIT trap (F38), so
# per-site cleanup cannot be relied on: TMPDIR rooting lets the runner remove
# everything in one rm -rf. Go and Python callers inherit it too.
RUN_TMP="$(cd "$(mktemp -d)" && pwd -P)"
export TMPDIR="$RUN_TMP"
TMP="$(cd "$(mktemp -d)" && pwd -P)"

# Black-box target (#46): sections call "$HV_BIN <group> <verb>". It defaults
# to the temporary shim, which maps verbs onto the old bin/ helpers; point it
# at a real `hv` binary to run the same sections against the Go port. The
# shim runs helpers from a copy of bin/ staged outside every project, so a
# helper that walks up from its own directory can never reach this dev tree.
export HV_BIN="${HV_BIN:-$TESTDIR/hv-shim}"
HV_SHIM_STAGE="$(mktemp -d)"
export HV_SHIM_HELPERS="$HV_SHIM_STAGE/bin"
cp -R "$BIN" "$HV_SHIM_HELPERS"
trap 'rm -rf "$RUN_TMP"' EXIT

# Forge and host guard: no section may reach a real gh, glab, herdr or tmux.
# The round runs inside herdr, so a real herdr or tmux call could close live
# agents' panes. Poison stand-ins sit first on PATH for every section; a
# section that wants a fake puts it in front of them, as it already does. A poison call logs itself
# and exits 99, and any logged call fails the run after the leak guard. A
# section that resets PATH must start it with "$HV_POISON_BIN".
export HV_POISON_BIN="$HV_SHIM_STAGE/poison"  # sections that reset PATH keep this first
HV_POISON_LOG="$HV_SHIM_STAGE/poison.log"
mkdir -p "$HV_POISON_BIN" && : > "$HV_POISON_LOG"
for cli in gh glab herdr tmux; do
  printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 99\n' "$cli" "$HV_POISON_LOG" > "$HV_POISON_BIN/$cli"
  chmod +x "$HV_POISON_BIN/$cli"
done
export PATH="$HV_POISON_BIN:$PATH"
# Nor may a section inherit this shell's live host identity (pane, tab,
# socket): sections that need one set fake values themselves.
for v in $(compgen -e | grep -E '^(HERDR_|TMUX)'); do unset "$v"; done

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
REPO_AGENTS="$REPO/AGENTS.md"
REPO_AGENTS_SNAP=""
if [ -f "$REPO_AGENTS" ]; then
  REPO_AGENTS_SNAP="$(mktemp)"
  cp "$REPO_AGENTS" "$REPO_AGENTS_SNAP"
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
#
# The loop runs in a subshell: sections replace the EXIT trap (F38), and the
# runner's own trap above must survive them to remove the shim stage.
# It is not written `( … ) || rc=$?`: bash ignores set -e inside a subshell
# that is the left side of `||`, so a failing section would carry on.
set +e
(
  set -e
  # SECTION_LIST (newline-separated paths, so paths may hold spaces) narrows
  # the run to those sections, in the order given: phase acceptance with
  # test/hv-hybrid runs only the sections a phase owns. Unset runs them all.
  sections=()
  if [ -n "${SECTION_LIST:-}" ]; then
    while IFS= read -r f; do [ -n "$f" ] && sections+=("$f"); done <<<"$SECTION_LIST"
  else
    sections=("$TESTDIR/sections/"*.sh)
  fi
  for f in "${sections[@]}"; do
    [ -f "$f" ] || continue
    cd "$TMP"
    source "$f"
  done
)
SECTIONS_RC=$?
set -e

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
if [ -n "$REPO_AGENTS_SNAP" ] && ! cmp -s "$REPO_AGENTS_SNAP" "$REPO_AGENTS"; then
  printf '\n\033[31merror: smoke leaked into %s — restoring from snapshot\033[0m\n' "$REPO_AGENTS" >&2
  cp "$REPO_AGENTS_SNAP" "$REPO_AGENTS"
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
[ -n "$REPO_AGENTS_SNAP" ] && rm -f "$REPO_AGENTS_SNAP"
[ -n "$REPO_HV_SNAP" ] && rm -rf "$REPO_HV_SNAP"
# Temp-dir guard (#110): everything the run made is under $RUN_TMP. Entries
# other than the runner's own were left behind by sections, helpers or the
# shim; report the count so growth shows up, then the EXIT trap removes it all.
RUN_LEFT="$(find "$RUN_TMP" -mindepth 1 -maxdepth 1 ! -path "$TMP" ! -path "$HV_SHIM_STAGE" 2>/dev/null | wc -l | tr -d ' ')"
[ "$RUN_LEFT" -eq 0 ] || printf 'note: %s temp entries left under %s by sections; removing them\n' "$RUN_LEFT" "$RUN_TMP" >&2
if [ "$RUN_LEFT" -gt "${HV_SMOKE_TMP_MAX:-150}" ]; then
  printf '\n\033[31merror: %s temp entries left under %s (limit %s); a section or helper is leaking\033[0m\n' "$RUN_LEFT" "$RUN_TMP" "${HV_SMOKE_TMP_MAX:-150}" >&2
  LEAKED=1
fi
[ "$LEAKED" = 1 ] && exit 1
if [ -s "$HV_POISON_LOG" ]; then
  printf '\n\033[31merror: a section called a real forge or host CLI (poison gh/glab/herdr/tmux on PATH):\033[0m\n' >&2
  sed 's/^/  /' "$HV_POISON_LOG" >&2
  exit 1
fi
[ "$SECTIONS_RC" = 0 ] || exit "$SECTIONS_RC"
# Phase acceptance (#49): with HV_HYBRID_EXPECT=<group,...> the run only counts
# if every one of those verb groups was served by the Go binary, never the shim.
if [ -n "${HV_HYBRID_EXPECT:-}" ]; then
  "$TESTDIR/hv-hybrid" --check || exit 1
fi

printf '\n\033[32mAll smoke tests passed.\033[0m\n'
