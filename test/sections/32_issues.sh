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

# hv-capture/SKILL.md — Step I6 labeling gate (folded from /hv-issues in F16)
grep -q "Step I6" "$REPO/hv-capture/SKILL.md" || \
  fail "hv-capture/SKILL.md missing Step I6 (Import Mode label gate)"

# hv-capture/SKILL.md — Step R3 de-tag gate (folded from /hv-rm in F14)
grep -q "Step R3" "$REPO/hv-capture/SKILL.md" || \
  fail "hv-capture/SKILL.md missing Step R3 (Remove Mode de-tag gate)"

# Both gates share the canonical callout phrasing — verify it's present at least twice
gate_count=$(grep -c '\*\*always manual\*\* — never auto-invoked, regardless of `autonomy.level`' \
  "$REPO/hv-capture/SKILL.md")
[ "$gate_count" -ge 2 ] || \
  fail "hv-capture/SKILL.md has $gate_count manual-gate callouts, expected ≥2 (Step R3 + Step I6)"

# hv-ship/SKILL.md — Step 6c direct-push close gate
grep -q "Step 6c" "$REPO/hv-ship/SKILL.md" || \
  fail "hv-ship/SKILL.md missing Step 6c (direct-push close gate)"
grep -q '\*\*always manual\*\* — never auto-invoked, regardless of `autonomy.level`' \
  "$REPO/hv-ship/SKILL.md" || fail "hv-ship/SKILL.md missing manual-gate callout (Step 6c)"

pass "3 manual-gate callouts present in hv-capture/SKILL.md (Step R3 + Step I6), hv-ship/SKILL.md (Step 6c)"

# === references/manual-gates.md inventory rows (T11 must land before these pass) ===
echo "Section 32: manual-gates.md inventory rows"

grep -q 'Step I6\|hv-capture --from-.*label\|label.*hv-capture --from' "$REPO/references/manual-gates.md" || \
  fail "manual-gates.md missing /hv-capture --from-* Step I6 row"

grep -q 'Step R3\|hv-capture --remove.*de-tag\|de-tag.*hv-capture --remove' "$REPO/references/manual-gates.md" || \
  fail "manual-gates.md missing /hv-capture --remove Step R3 row"

grep -q 'Step 6c\|direct-push close' "$REPO/references/manual-gates.md" || \
  fail "manual-gates.md missing hv-ship Step 6c row (T11 not yet landed?)"

pass "manual-gates.md inventory has rows for the 3 manual gates"

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

# === hv-issues-imported --open-only smoke (F77) ===
echo "Section 32: hv-issues-imported --open-only flag"
TMP_OO="$(mktemp -d)"
trap 'rm -rf "$TMP_OO"; trap '"'"'rm -rf "$TMP"'"'"' EXIT' EXIT

mkdir -p "$TMP_OO/.hv/bugs" "$TMP_OO/.hv/features" "$TMP_OO/.hv/tasks"

# Seed BACKLOG with GH + GL refs the post-filter has to probe upstream for.
cat > "$TMP_OO/.hv/BACKLOG.md" <<'EOF'
# TODO

## Features

- **[F01] [Major] Test feature.** Body. GH: #999999

## Bugs

- **[B01] [P1] Test bug.** GL: #999999

## Tasks

## Completed
EOF

# Without --open-only: both entries should appear (existing behavior preserved).
out_all=$(cd "$TMP_OO" && "$REPO/bin/hv-issues-imported") || \
  fail "hv-issues-imported (no flag) exited non-zero on --open-only fixture"
count_all=$(echo "$out_all" | jq 'length')
[ "$count_all" = "2" ] || fail "hv-issues-imported (no flag) expected 2 entries on F77 fixture, got $count_all"

# With --open-only and no gh/glab on PATH: every entry fails the state probe
# silently, so the result is []. Proves the flag is recognized, doesn't error
# out on missing CLIs, and emits a JSON array.
out_oo=$(cd "$TMP_OO" && env PATH=/usr/bin:/bin "$REPO/bin/hv-issues-imported" --open-only) || \
  fail "hv-issues-imported --open-only exited non-zero with stripped PATH"
echo "$out_oo" | jq -e '. == []' >/dev/null || \
  fail "hv-issues-imported --open-only with no gh/glab expected [], got $out_oo"

# --open-only is orthogonal to --repo: combining them parses fine and still
# emits a JSON array (here empty because the only Repos:-tagged entries don't
# match 'nonexistent').
out_combo=$(cd "$TMP_OO" && env PATH=/usr/bin:/bin "$REPO/bin/hv-issues-imported" --repo nonexistent --open-only) || \
  fail "hv-issues-imported --repo nonexistent --open-only exited non-zero"
echo "$out_combo" | jq -e 'type == "array"' >/dev/null || \
  fail "hv-issues-imported --repo … --open-only expected JSON array, got $out_combo"

trap 'rm -rf "$TMP"' EXIT
pass "hv-issues-imported --open-only filters by upstream state, no-ops gracefully without gh/glab"
