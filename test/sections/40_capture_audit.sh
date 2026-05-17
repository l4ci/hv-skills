echo "F27 hv-capture-audit — surfaces ship evidence for stale milestone-spec captures"

# Builds a fixture repo with a few commits whose subjects mention specific
# helper names + paths, then asserts hv-capture-audit:
#   - exits 2 with a matching report for titles whose distinctive tokens
#     appear in commit subjects
#   - exits 0 silently for titles with no overlap
#   - exits 1 on missing args
#
# The audit is heuristic — keyword grep against `git log` + path existence.
# False-positive tolerance is acceptable; false-negatives (missing a shipped
# title) defeat the purpose, so the assertions favor wide token shapes.

TMP_AUDIT="$(mktemp -d)"
trap 'rm -rf "$TMP_AUDIT"' EXIT
cd "$TMP_AUDIT"
git init -q
git config user.email t@t
git config user.name t

mkdir -p bin runner
cat > runner/postgres.go <<'EOF'
package runner
EOF
cat > bin/hv-flagship <<'EOF'
#!/bin/sh
EOF
chmod +x bin/hv-flagship
git add -A
git commit -q -m "seed runner/postgres.go and bin/hv-flagship"
git commit --allow-empty -q -m "feat: implement Driver for postgres backend [F76]"
git commit --allow-empty -q -m "refactor: rename bin/hv-flagship to bin/hv-flagship-v2"

# Exit 2: a title whose tokens hit a real commit subject.
OUT="$("$BIN/hv-capture-audit" "Implement Driver for postgres backend" 2>&1)" || RC=$?
RC=${RC:-0}
[ "$RC" = "2" ] || fail "hv-capture-audit exit code: expected 2 on matched title, got $RC"
echo "$OUT" | grep -q "STRONG" || fail "hv-capture-audit did not emit [STRONG] for matched title (output: $OUT)"
echo "$OUT" | grep -q "F76" || fail "hv-capture-audit report missing the F76 commit reference (output: $OUT)"
pass "F27 audit — exit 2 + STRONG match on shipped title"

# Path match: title contains `runner/postgres.go`, which exists.
unset RC
OUT_PATH="$("$BIN/hv-capture-audit" "Add tests for \`runner/postgres.go\`" 2>&1)" || RC=$?
RC=${RC:-0}
[ "$RC" = "2" ] || fail "hv-capture-audit exit code: expected 2 on path-match, got $RC"
echo "$OUT_PATH" | grep -q "PATH" || fail "hv-capture-audit did not emit [PATH] for an existing file (output: $OUT_PATH)"
pass "F27 audit — exit 2 + PATH marker when title names an existing file"

# Exit 0: a title with no overlap. Use distinctive made-up tokens so common
# words like "session" don't accidentally hit prior commits.
unset RC
OUT_CLEAN="$("$BIN/hv-capture-audit" "Add zorblax-foofoo zonkmind handler" 2>&1)" || RC=$?
RC=${RC:-0}
[ "$RC" = "0" ] || fail "hv-capture-audit exit code: expected 0 on no-overlap title, got $RC (output: $OUT_CLEAN)"
[ -z "$OUT_CLEAN" ] || fail "hv-capture-audit emitted output on clean title (expected silent): $OUT_CLEAN"
pass "F27 audit — exit 0 silent on titles with no ship evidence"

# Exit 1: usage error on no args.
unset RC
"$BIN/hv-capture-audit" 2>/dev/null && RC=$? || RC=$?
[ "$RC" = "1" ] || fail "hv-capture-audit exit code: expected 1 on missing args, got $RC"
pass "F27 audit — exit 1 with usage on missing args"

# Multi-arg: clean + flagged in one call returns 2 (any flag wins).
unset RC
OUT_MIX="$("$BIN/hv-capture-audit" "Add zorblax-foofoo zonkmind handler" "Implement Driver for postgres backend" 2>&1)" || RC=$?
RC=${RC:-0}
[ "$RC" = "2" ] || fail "hv-capture-audit exit code: expected 2 when any input flags, got $RC"
echo "$OUT_MIX" | grep -q "Implement Driver" || fail "multi-arg audit did not report on the flagged title"
echo "$OUT_MIX" | grep -q "zorblax" && fail "multi-arg audit reported on the clean title (should be silent)"
pass "F27 audit — multi-arg call reports only the flagged titles"

cd "$TMP"
trap 'rm -rf "$TMP"' EXIT
