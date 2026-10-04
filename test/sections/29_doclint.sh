echo "doclint: no skill or reference names a legacy helper (A9 #53)"
# test/validate-skills.py fails any rota-*/*.md or references/*.md line that
# names an old bin/ helper, the .hv/bin mirror or hvlib, except in files on its
# UNCONVERTED list. Each A9 slice removes its own entries when it converts them,
# and an entry for a clean or missing file fails, so the list only shrinks.
# Fixture strings are assembled from fragments so this file never trips the
# scan in section 72.
VALIDATE="$TESTDIR/validate-skills.py"
DL_TMP="$(mktemp -d)"
MIRROR='.hv/''bin'
LIB='hv''lib'
SK='SKILL''.md'

# A fixture repo: one skill, one reference, a changelog.
dl_fixture() {
  local d="$1"
  mkdir -p "$d/rota-a" "$d/references"
  printf -- '---\nname: rota-a\ndescription: test\n---\n\nRun `rota status show`. See /hv-rm and /rota-release.\n' > "$d/rota-a/$SK"
  printf '# ref\n\nUse `rota config set`; hv-skills owns this.\n' > "$d/references/r.md"
  printf '# Changelog\n\n## v1.0.0\n' > "$d/CHANGELOG.md"
}
# dl_run <dir> <allowlist> prints the validator output and returns its exit code.
# ROTA_DOCLINT_PROSE=off: the fixtures carry no real skills, so the prose lint is off.
dl_run() { ( cd "$1" && ROTA_DOCLINT_PROSE=off ROTA_SPEC_PENDING="" ROTA_DOCLINT_UNCONVERTED="$2" python3 "$VALIDATE" 2>&1 ); }

F="$DL_TMP/clean"; dl_fixture "$F"
OUT="$(dl_run "$F" "")" || fail "doclint flagged a clean fixture (slash commands, hv-skills, rota verbs): $OUT"
pass "clean prose, slash commands and a skill name pass"

# Every legacy form fails, in a skill, a nested skill file and a reference.
N=0
for S in 'run hv-config-set x y' "ls $MIRROR/x" "from $LIB import x" 'run ${CLAUDE_PLUGIN_ROOT}/bin/''hv-summary' 'source hv-preamble.sh'; do
  for T in rota-a/$SK rota-a/notes.md references/r.md; do
    N=$((N + 1)); F="$DL_TMP/bad$N"; dl_fixture "$F"
    printf '\n%s\n' "$S" >> "$F/$T"
    RC=0; OUT="$(dl_run "$F" "")" || RC=$?
    [ "$RC" = 1 ] || fail "doclint passed '$S' in $T (rc $RC): $OUT"
    grep -qF "$T:" <<<"$OUT" || fail "doclint did not name $T for '$S': $OUT"
  done
done
pass "legacy helper names, the mirror, the helper library and bin/ paths fail in skills and references"

# The transition allowlist: a listed dirty file passes; a listed clean or
# missing file fails, so slices must drop their entries as they convert.
F="$DL_TMP/allow"; dl_fixture "$F"
printf '\nrun hv-config-set x y\n' >> "$F/rota-a/$SK"
OUT="$(dl_run "$F" "rota-a/$SK")" || fail "doclint flagged a file on the allowlist: $OUT"
RC=0; OUT="$(dl_run "$F" "rota-a/$SK references/r.md")" || RC=$?
[ "$RC" = 1 ] && grep -qF "references/r.md: no legacy names left" <<<"$OUT" \
  || fail "doclint kept a clean file on the allowlist (rc $RC): $OUT"
RC=0; OUT="$(dl_run "$F" "rota-a/$SK rota-gone/$SK")" || RC=$?
[ "$RC" = 1 ] && grep -qF "rota-gone/$SK: listed in UNCONVERTED but missing" <<<"$OUT" \
  || fail "doclint kept a missing file on the allowlist (rc $RC): $OUT"
pass "the UNCONVERTED allowlist exempts listed files and rejects stale entries"

# The real tree, with the built-in allowlist.
OUT="$(cd "$REPO" && python3 "$VALIDATE" 2>&1)" || fail "validate-skills fails on the repo: $OUT"
pass "skills and references pass the doclint"

# The prose lint (#173): drop a pinned phrase from a copy of the real skills and
# the validator names the file; a deleted target file is reported, not skipped.
# white-box-begin: A9 #53 doclint
PL="$DL_TMP/prose"; mkdir -p "$PL"
cp -R "$REPO"/rota-* "$REPO/references" "$REPO/docs" "$REPO/README.md" "$REPO/CHANGELOG.md" "$PL/"
OUT="$(cd "$PL" && python3 "$VALIDATE" 2>&1)" || fail "prose lint fails on a copy of the repo: $OUT"
sed -i 's/rota status loop start/rota status loop begin/' "$PL/rota-work/$SK"
RC=0; OUT="$(cd "$PL" && python3 "$VALIDATE" 2>&1)" || RC=$?
[ "$RC" = 1 ] && grep -qF "rota-work/$SK: must call rota status loop start" <<<"$OUT" \
  || fail "prose lint missed a dropped phrase (rc $RC): $OUT"
rm -f "$PL/references/manual-gates.md"
RC=0; OUT="$(cd "$PL" && python3 "$VALIDATE" 2>&1)" || RC=$?
[ "$RC" = 1 ] && grep -qF "references/manual-gates.md: prose rule target is missing" <<<"$OUT" \
  || fail "prose lint skipped a missing target file (rc $RC): $OUT"
# white-box-end
pass "the prose lint names a skill that lost a pinned phrase and a missing target file"

rm -rf "${DL_TMP:?}"
