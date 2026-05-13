#!/usr/bin/env bash
# Section 32 — hv-issues — helper existence + provider detection + manual-gate callouts.
# F38 local-trap convention: each tmp tree installs its own trap; restore global before
# the section's final pass line. (Helpers pass/fail and $REPO/$TMP from runner.sh/lib.sh.)
set -euo pipefail

# === Helper existence + executable mode (F66) ===
echo "Section 32: hv-issues helper existence + mode"
for h in hv-issues-provider hv-issues-list hv-issues-label hv-issues-close hv-issues-imported; do
  [ -f "$REPO/bin/$h" ] || fail "bin/$h missing"
  mode=$(git -C "$REPO" ls-files -s "bin/$h" | awk '{print $1}')
  [ "$mode" = "100755" ] || fail "bin/$h tracked mode is $mode, expected 100755"
done
pass "5 hv-issues-* helpers exist and tracked as 100755"

# === Provider detection unit tests ===
echo "Section 32: hv-issues-provider classification"
TMP_PROV="$(mktemp -d)"
trap 'rm -rf "$TMP_PROV"; trap '"'"'rm -rf "$TMP"'"'"' EXIT' EXIT

(
  cd "$TMP_PROV"
  git init -q
  git config user.email t@t
  git config user.name t

  # Test 1: github.com SSH
  git remote add origin "git@github.com:foo/bar.git"
  out=$("$REPO/bin/hv-issues-provider")
  [ "$out" = "github" ] || { echo "github.com SSH → $out, expected github"; exit 1; }

  # Test 2: gitlab.com HTTPS
  git remote set-url origin "https://gitlab.com/foo/bar.git"
  out=$("$REPO/bin/hv-issues-provider")
  [ "$out" = "gitlab" ] || { echo "gitlab.com HTTPS → $out, expected gitlab"; exit 1; }

  # Test 3: self-hosted GitLab SSH
  git remote set-url origin "git@gitlab.example.com:foo/bar.git"
  out=$("$REPO/bin/hv-issues-provider")
  [ "$out" = "gitlab" ] || { echo "self-hosted gitlab SSH → $out, expected gitlab"; exit 1; }

  # Test 4: GitHub Enterprise HTTPS
  git remote set-url origin "https://github.company.com/foo/bar.git"
  out=$("$REPO/bin/hv-issues-provider")
  [ "$out" = "github" ] || { echo "GH Enterprise HTTPS → $out, expected github"; exit 1; }

  # Test 5: no origin at all
  git remote remove origin
  out=$("$REPO/bin/hv-issues-provider")
  [ "$out" = "unknown" ] || { echo "no origin → $out, expected unknown"; exit 1; }
) || fail "hv-issues-provider classification failed (see subshell output above)"

trap 'rm -rf "$TMP"' EXIT
pass "hv-issues-provider classifies github/gitlab/unknown across 5 fixtures"

# === SKILL.md manual-gate callouts (T7, T8, T9) ===
echo "Section 32: manual-gate callouts in SKILL.md files"

# hv-issues/SKILL.md — Step 7 labeling gate
grep -q '\*\*always manual\*\* — never auto-invoked, regardless of `autonomy.level`' \
  "$REPO/hv-issues/SKILL.md" || fail "hv-issues/SKILL.md missing manual-gate callout (Step 7)"

# hv-rm/SKILL.md — Step 3.5 de-tag gate
grep -q '\*\*always manual\*\* — never auto-invoked, regardless of `autonomy.level`' \
  "$REPO/hv-rm/SKILL.md" || fail "hv-rm/SKILL.md missing manual-gate callout (Step 3.5)"

# hv-ship/SKILL.md — Step 6c direct-push close gate
grep -q "Step 6c" "$REPO/hv-ship/SKILL.md" || \
  fail "hv-ship/SKILL.md missing Step 6c (direct-push close gate)"
grep -q '\*\*always manual\*\* — never auto-invoked, regardless of `autonomy.level`' \
  "$REPO/hv-ship/SKILL.md" || fail "hv-ship/SKILL.md missing manual-gate callout (Step 6c)"

pass "3 manual-gate callouts present in hv-issues/SKILL.md, hv-rm/SKILL.md, hv-ship/SKILL.md"

# === references/manual-gates.md inventory rows (T11 must land before these pass) ===
echo "Section 32: manual-gates.md inventory rows"

[ "$(grep -c '/hv-issues' "$REPO/references/manual-gates.md")" -ge 1 ] || \
  fail "manual-gates.md missing /hv-issues row (T11 not yet landed?)"

grep -q 'Step 3\.5\|hv-rm.*de-tag\|de-tag.*hv-rm' "$REPO/references/manual-gates.md" || \
  fail "manual-gates.md missing hv-rm Step 3.5 row (T11 not yet landed?)"

grep -q 'Step 6c\|direct-push close' "$REPO/references/manual-gates.md" || \
  fail "manual-gates.md missing hv-ship Step 6c row (T11 not yet landed?)"

pass "manual-gates.md inventory has rows for the 3 new gates"

# === hv-issues-imported smoke ===
echo "Section 32: hv-issues-imported smoke"
TMP_IMP="$(mktemp -d)"
trap 'rm -rf "$TMP_IMP"; trap '"'"'rm -rf "$TMP"'"'"' EXIT' EXIT

mkdir -p "$TMP_IMP/.hv/bugs" "$TMP_IMP/.hv/features" "$TMP_IMP/.hv/tasks"

# Seed a minimal BACKLOG.md with one GH and one GL cross-reference
cat > "$TMP_IMP/.hv/BACKLOG.md" <<'EOF'
# TODO

## Features

- **[F01] [Major] Test feature.** Body. GH: #999 Repos: web

## Bugs

- **[B01] [P1] Test bug.** GL: #42

## Tasks

## Completed
EOF

# Run from inside the fake tree so hv-self-locate resolves .hv/
out=$(cd "$TMP_IMP" && "$REPO/bin/hv-issues-imported") || \
  fail "hv-issues-imported exited non-zero on fixture BACKLOG"

count=$(echo "$out" | jq 'length')
[ "$count" = "2" ] || fail "hv-issues-imported expected 2 entries, got $count — output: $out"

echo "$out" | jq -e '.[] | select(.issue == 999 and .provider == "github")' >/dev/null || \
  fail "hv-issues-imported missing github #999 entry"

echo "$out" | jq -e '.[] | select(.issue == 42 and .provider == "gitlab")' >/dev/null || \
  fail "hv-issues-imported missing gitlab #42 entry"

# Remove the GH bullet; re-run; expect length 1
cat > "$TMP_IMP/.hv/BACKLOG.md" <<'EOF'
# TODO

## Features

## Bugs

- **[B01] [P1] Test bug.** GL: #42

## Tasks

## Completed
EOF

out2=$(cd "$TMP_IMP" && "$REPO/bin/hv-issues-imported")
count2=$(echo "$out2" | jq 'length')
[ "$count2" = "1" ] || fail "hv-issues-imported expected 1 entry after removing GH bullet, got $count2"

trap 'rm -rf "$TMP"' EXIT
pass "hv-issues-imported indexes GH/GL refs from a fixture BACKLOG"
