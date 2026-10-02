#!/usr/bin/env bash
# Section 32 — hv issues — helper existence + provider detection + manual-gate callouts.
# F38 local-trap convention: each tmp tree installs its own trap; restore global before
# the section's final pass line. (Helpers pass/fail and $REPO/$TMP from runner.sh/lib.sh.)
set -euo pipefail

# === Helper existence + executable mode (F66) ===
# white-box-begin: A9 #53 keep
echo "Section 32: hv-issues helper existence + mode"
for h in hv-issues-provider hv-issues-list hv-issues-label hv-issues-close hv-issues-imported; do
  [ -f "$REPO/bin/$h" ] || fail "bin/$h missing"
  mode=$(git -C "$REPO" ls-files -s "bin/$h" | awk '{print $1}')
  [ "$mode" = "100755" ] || fail "bin/$h tracked mode is $mode, expected 100755"
done
pass "5 hv-issues-* helpers exist and tracked as 100755"
# white-box-end

# === Provider detection unit tests ===
echo "Section 32: issues provider classification"
TMP_PROV="$(mktemp -d)"
trap 'rm -rf "$TMP_PROV"; trap '"'"'rm -rf "$TMP"'"'"' EXIT' EXIT

(
  cd "$TMP_PROV"
  mkdir -p .hv
  git init -q
  git config user.email t@t
  git config user.name t

  # Test 1: github.com SSH
  git remote add origin "git@github.com:foo/bar.git"
  out=$("$HV_BIN" --json issues provider | jget data.provider)
  [ "$out" = "github" ] || { echo "github.com SSH → $out, expected github"; exit 1; }

  # Test 2: gitlab.com HTTPS
  git remote set-url origin "https://gitlab.com/foo/bar.git"
  out=$("$HV_BIN" --json issues provider | jget data.provider)
  [ "$out" = "gitlab" ] || { echo "gitlab.com HTTPS → $out, expected gitlab"; exit 1; }

  # Test 3: self-hosted GitLab SSH
  git remote set-url origin "git@gitlab.example.com:foo/bar.git"
  out=$("$HV_BIN" --json issues provider | jget data.provider)
  [ "$out" = "gitlab" ] || { echo "self-hosted gitlab SSH → $out, expected gitlab"; exit 1; }

  # Test 4: GitHub Enterprise HTTPS
  git remote set-url origin "https://github.company.com/foo/bar.git"
  out=$("$HV_BIN" --json issues provider | jget data.provider)
  [ "$out" = "github" ] || { echo "GH Enterprise HTTPS → $out, expected github"; exit 1; }

  # Test 5: no origin at all
  git remote remove origin
  out=$("$HV_BIN" --json issues provider | jget data.provider)
  [ "$out" = "unknown" ] || { echo "no origin → $out, expected unknown"; exit 1; }
) || fail "issues provider classification failed (see subshell output above)"

trap 'rm -rf "$TMP"' EXIT
pass "issues provider classifies github/gitlab/unknown across 5 fixtures"

# === SKILL.md manual-gate callouts (T7, T8, T9) ===
# white-box-begin: A9 #53 doclint
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
# white-box-end

# === issues imported smoke ===
echo "Section 32: issues imported smoke"
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
out=$(cd "$TMP_IMP" && hvj issues imported) || \
  fail "issues imported exited non-zero on fixture BACKLOG"

count=$(echo "$out" | jq '.data.entries | length')
[ "$count" = "2" ] || fail "issues imported expected 2 entries, got $count — output: $out"

echo "$out" | jq -e '.data.entries[] | select(.issue == 999 and .provider == "github" and .itemId == "F01" and .repo == "web" and .status == "open")' >/dev/null || \
  fail "issues imported missing github #999 entry"

echo "$out" | jq -e '.data.entries[] | select(.issue == 42 and .provider == "gitlab" and .itemId == "B01" and .repo == null)' >/dev/null || \
  fail "issues imported missing gitlab #42 entry"

# Remove the GH bullet; re-run; expect length 1
cat > "$TMP_IMP/.hv/BACKLOG.md" <<'EOF'
# TODO

## Features

## Bugs

- **[B01] [P1] Test bug.** GL: #42

## Tasks

## Completed
EOF

out2=$(cd "$TMP_IMP" && hvj issues imported)
count2=$(echo "$out2" | jq '.data.entries | length')
[ "$count2" = "1" ] || fail "issues imported expected 1 entry after removing GH bullet, got $count2"

trap 'rm -rf "$TMP"' EXIT
pass "issues imported indexes GH/GL refs from a fixture BACKLOG"

# === issues imported --open-only smoke (F77) ===
echo "Section 32: issues imported --open-only flag"
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
out_all=$(cd "$TMP_OO" && hvj issues imported) || \
  fail "issues imported (no flag) exited non-zero on --open-only fixture"
count_all=$(echo "$out_all" | jq '.data.entries | length')
[ "$count_all" = "2" ] || fail "issues imported (no flag) expected 2 entries on F77 fixture, got $count_all"

# With --open-only, every entry fails the state probe silently, so the result
# is []. Two ways to fail: no gh/glab on PATH at all, and a gh/glab that fails
# every call. NOGH links every tool from /usr/bin and /bin except gh, glab, herdr and tmux:
# a real "CLI missing" PATH that can't reach a real forge (the runner's poison
# stand-ins would count as present).
NOGH="$TMP_OO/nogh-bin"; mkdir -p "$NOGH"
for d in /usr/bin /bin; do
  for t in "$d"/*; do
    n="${t##*/}"; case "$n" in gh|glab|herdr|tmux) continue ;; esac
    [ -e "$NOGH/$n" ] || ln -s "$t" "$NOGH/$n"
  done
done
out_oo=$(cd "$TMP_OO" && env PATH="$NOGH" "$HV_BIN" --json issues imported --open-only) || \
  fail "issues imported --open-only exited non-zero with no gh/glab on PATH"
echo "$out_oo" | jq -e '.data.entries == []' >/dev/null || \
  fail "issues imported --open-only with no gh/glab expected no entries, got $out_oo"
out_oo=$(cd "$TMP_OO" && env -u FAKE_TRACKER_DB -u FAKE_TRACKER_LOG PATH="$TESTDIR/fakes:$PATH" "$HV_BIN" --json issues imported --open-only) || \
  fail "issues imported --open-only exited non-zero with a failing gh/glab"
echo "$out_oo" | jq -e '.data.entries == []' >/dev/null || \
  fail "issues imported --open-only with a failing gh/glab expected no entries, got $out_oo"

# --open-only is orthogonal to --for-repo: combining them parses fine and still
# emits an entries array (empty: no Repos:-tagged entry matches 'nonexistent').
out_combo=$(cd "$TMP_OO" && env PATH="$NOGH" "$HV_BIN" --json issues imported --for-repo nonexistent --open-only) || \
  fail "issues imported --for-repo nonexistent --open-only exited non-zero"
echo "$out_combo" | jq -e '.data.entries | type == "array"' >/dev/null || \
  fail "issues imported --for-repo … --open-only expected an entries array, got $out_combo"

# The old --repo spelling is the global flag now; imported has no repo scope.
rc=0; (cd "$TMP_OO" && "$HV_BIN" issues imported --repo nonexistent >/dev/null 2>&1) || rc=$?
[ "$rc" = "2" ] || fail "issues imported --repo should exit 2 (no repo scope), got $rc"

trap 'rm -rf "$TMP"' EXIT
pass "issues imported --open-only filters by upstream state, no-ops gracefully without gh/glab"

# === issues list / label / close ===
echo "Section 32: issues list, label and close against the fake forges"
TMP_IV="$(mktemp -d)"
trap 'rm -rf "$TMP_IV"; trap '"'"'rm -rf "$TMP"'"'"' EXIT' EXIT

for prov in github gitlab; do
  P="$TMP_IV/$prov"; mkdir -p "$P/.hv"
  echo "{\"issues\":{\"provider\":\"$prov\",\"retryWaitSeconds\":0}}" > "$P/.hv/config.json"
  (
    cd "$P"
    git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m seed
    # issues list/label/close detect the provider from origin, not from issues.provider
    git remote add origin "https://$prov.com/o/r.git"
    SHA=$(git rev-parse HEAD)
    export PATH="$TESTDIR/fakes:$PATH" FAKE_TRACKER_DB="$P/db.json" FAKE_TRACKER_LOG="$P/log"
    [ "$(command -v "$([ "$prov" = github ] && echo gh || echo glab)")" = "$TESTDIR/fakes/$([ "$prov" = github ] && echo gh || echo glab)" ] || fail "$prov: fake forge CLI not first on PATH"
    eq() { [ "$2" = "$3" ] || fail "$prov issues $1: expected [$2] got [$3]"; }
    rcof() { local rc=0; "$@" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
    # The fake store is the forge's own state; no verb reads raw labels, state or comments.
    DBQ() { python3 -c '
import json, sys
n = int(sys.argv[2]); i = next(i for i in json.load(open(sys.argv[3]))["issues"] if i["number"] == n)
print({"labels": ",".join(sorted(i["labels"])), "state": i["state"].lower(),
       "comments": len(i["comments"])}[sys.argv[1]])' "$1" "$2" "$P/db.json"; }
    if [ "$prov" = github ]; then
      gh label create bug >/dev/null && gh issue create -t "first" -b "body one" -l bug >/dev/null && gh issue create -t "second" -b "body two" >/dev/null
    else
      glab issue create -t "first" -d "body one" -l bug >/dev/null && glab issue create -t "second" -d "body two" >/dev/null
    fi

    # list: both open issues, newest first, normalised shape
    OUT=$(hvj issues list) || fail "$prov issues list failed: $OUT"
    eq "list count" 2 "$(echo "$OUT" | jq '.data.issues | length')"
    eq "list numbers" "2,1" "$(echo "$OUT" | jq -r '[.data.issues[].number] | join(",")')"
    eq "list first title" "first" "$(echo "$OUT" | jq -r '.data.issues[] | select(.number == 1) | .title')"
    eq "list first labels" "bug" "$(echo "$OUT" | jq -r '.data.issues[] | select(.number == 1) | .labels | join(",")')"
    eq "list first body" "body one" "$(echo "$OUT" | jq -r '.data.issues[] | select(.number == 1) | .body')"
    echo "$OUT" | jq -e '.data.issues[0] | has("url") and has("author")' >/dev/null || fail "$prov issues list entry misses url/author: $OUT"
    OUT=$(hvj issues list --label bug) || fail "$prov issues list --label failed"
    eq "list --label" "1" "$(echo "$OUT" | jq -r '[.data.issues[].number] | join(",")')"
    OUT=$(hvj issues list --limit 1) || fail "$prov issues list --limit failed"
    eq "list --limit" "1" "$(echo "$OUT" | jq '.data.issues | length')"
    eq "list --limit 0 is usage" 2 "$(rcof "$HV_BIN" --json issues list --limit 0)"

    # label: add, remove, usage and a missing issue
    OUT=$(hvj issues label 2 --add triage) || fail "$prov issues label --add failed: $OUT"
    eq "label add data" "2 triage add true" "$(echo "$OUT" | jq -r '.data | "\(.issue) \(.label) \(.action) \(.changed)"')"
    eq "label add state" "triage" "$(DBQ labels 2)"
    OUT=$(hvj issues label 2 --remove triage) || fail "$prov issues label --remove failed: $OUT"
    eq "label remove data" "2 triage remove" "$(echo "$OUT" | jq -r '.data | "\(.issue) \(.label) \(.action)"')"
    eq "label remove state" "" "$(DBQ labels 2)"
    eq "label needs one of add/remove" 2 "$(rcof "$HV_BIN" --json issues label 2)"
    eq "label rejects add+remove" 2 "$(rcof "$HV_BIN" --json issues label 2 --add a --remove b)"
    eq "label missing issue" 5 "$(rcof "$HV_BIN" --json issues label 99 --add triage)"

    # close: closes once and comments with the short sha; a repeat posts no second comment
    OUT=$(hvj issues close 2 --commit "$SHA" --item B07) || fail "$prov issues close failed: $OUT"
    eq "close data" "2 $SHA true" "$(echo "$OUT" | jq -r '.data | "\(.issue) \(.commit) \(.changed)"')"
    eq "close state" closed "$(DBQ state 2)"
    eq "close comment" 1 "$(DBQ comments 2)"
    eq "other issue untouched" open "$(DBQ state 1)"
    hvj issues close 2 --commit "$SHA" >/dev/null || fail "$prov repeat close should exit 0"
    eq "repeat close adds no comment" 1 "$(DBQ comments 2)"
    OUT=$(hvj issues list) || fail "$prov issues list after close failed"
    eq "list drops closed" "1" "$(echo "$OUT" | jq -r '[.data.issues[].number] | join(",")')"
    eq "close unknown commit" 3 "$(rcof "$HV_BIN" --json issues close 1 --commit deadbeef0000)"
    eq "close missing issue" 5 "$(rcof "$HV_BIN" --json issues close 99 --commit "$SHA")"
    eq "close without --commit" 2 "$(rcof "$HV_BIN" --json issues close 1)"
    eq "close non-numeric issue" 2 "$(rcof "$HV_BIN" --json issues close abc --commit "$SHA")"
  ) || fail "issues list/label/close on $prov failed (see subshell output above)"
done

trap 'rm -rf "$TMP"' EXIT
rm -rf "$TMP_IV"
pass "issues list, label and close behave on github and gitlab (data, store state, exit codes)"
